"""
Danotech Expenses - the Phase 05 OIDC / OAuth 2.0 demonstration app.

What it demonstrates
  OIDC       Sign-in with the authorization code flow + PKCE. The ID token proves WHO the user is.
  OAuth 2.0  The same sign-in returns an access token for Microsoft Graph (User.Read), used once to
             look up the user's manager. The access token is for an API; the ID token is for this app.
  App roles  Authorization comes from the `roles` claim in the ID token. Roles are assigned to
             Entra ID groups, and the groups are dynamic (driven by HR job codes), so access follows
             the HR record with no change in this app.
  SoD        Separation-of-duties rules from Phase 03 are enforced here, server-side. In particular
             the compensating control for exception EXC-001: nobody can pay a claim they approved.

Every decision is checked on the server. Hiding a button is a convenience, never a control.

Configuration (environment variables; never committed):
  TENANT_ID, CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, FLASK_SECRET_KEY
  EXPENSES_DB (optional; default instance/expenses.db)
"""
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from functools import wraps

import msal
import requests
from flask import Flask, abort, flash, g, redirect, render_template, request, session, url_for
from werkzeug.middleware.proxy_fix import ProxyFix

TENANT_ID = os.environ.get("TENANT_ID", "danotechinc.onmicrosoft.com")
CLIENT_ID = os.environ.get("CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "")
REDIRECT_URI = os.environ.get("REDIRECT_URI", "http://localhost:5000/auth/callback")
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
GRAPH_SCOPES = ["User.Read"]  # delegated: read the signed-in user's own profile and manager

# App role values, as defined in config/expenses-app-roles.json
ROLE_SUBMIT, ROLE_APPROVE, ROLE_REVIEW, ROLE_PAY, ROLE_AUDIT = (
    "Expenses.Submit", "Expenses.Approve", "Expenses.Review", "Expenses.Pay", "Expenses.Audit")
ROLE_INFO = {
    ROLE_SUBMIT: ("Submit", "BR-WORKFORCE", "GRP-DYN-ALL-Workforce"),
    ROLE_APPROVE: ("Approve team claims", "JR-PEOPLE-MANAGER", "GRP-DYN-JOB-PeopleManagers"),
    ROLE_REVIEW: ("Finance review", "JR-FIN-ACCOUNTING / JR-FIN-CONTROLLER", "GRP-DYN-JOB-FIN-ACCOUNTING, GRP-DYN-JOB-FIN-CONTROLLER"),
    ROLE_PAY: ("Release payment", "JR-FIN-AP / JR-FIN-CONTROLLER", "GRP-DYN-JOB-FIN-AP, GRP-DYN-JOB-FIN-CONTROLLER"),
    ROLE_AUDIT: ("Audit (read-only)", "JR-FIN-FPA / JR-LEGAL-COMPLIANCE / JR-SEC-GRC", "GRP-DYN-JOB-FIN-FPA, GRP-DYN-JOB-LEGAL-COMPLIANCE, GRP-DYN-JOB-SEC-GRC"),
}

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY") or os.urandom(32)
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)  # App Service terminates TLS in front of us
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=REDIRECT_URI.startswith("https://"),
)
DB_PATH = os.environ.get("EXPENSES_DB") or os.path.join(app.instance_path, "expenses.db")


# --------------------------------------------------------------------------- data
def db():
    if "db" not in g:
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def init_db():
    db().executescript("""
    CREATE TABLE IF NOT EXISTS claims (
        id TEXT PRIMARY KEY, created TEXT, submitter_oid TEXT, submitter_name TEXT, manager_oid TEXT,
        amount REAL, currency TEXT, category TEXT, description TEXT, status TEXT,
        approved_by_oid TEXT, approved_by_name TEXT, approved_at TEXT,
        reviewed_by_oid TEXT, reviewed_by_name TEXT, reviewed_at TEXT,
        paid_by_oid TEXT, paid_by_name TEXT, paid_at TEXT);
    CREATE TABLE IF NOT EXISTS audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, actor_oid TEXT, actor_name TEXT,
        action TEXT, claim_id TEXT, outcome TEXT, detail TEXT);
    """)
    db().commit()


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def audit(action, claim_id, outcome, detail=""):
    u = session.get("user", {})
    db().execute("INSERT INTO audit (ts, actor_oid, actor_name, action, claim_id, outcome, detail) VALUES (?,?,?,?,?,?,?)",
                 (now(), u.get("oid"), u.get("name"), action, claim_id, outcome, detail))
    db().commit()


# --------------------------------------------------------------------------- auth
def msal_app():
    return msal.ConfidentialClientApplication(CLIENT_ID, authority=AUTHORITY, client_credential=CLIENT_SECRET)


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapper


def roles():
    return set(session.get("user", {}).get("roles", []))


def require_role(role):
    """Server-side authorization. 403 and an audit entry if the token doesn't carry the role."""
    if role not in roles():
        audit(f"access:{role}", None, "Denied", "Role not present in token")
        abort(403, description=f"Your token doesn't include the {role} role.")


@app.route("/login")
def login():
    # MSAL adds PKCE (code_challenge) and a nonce/state automatically.
    flow = msal_app().initiate_auth_code_flow(GRAPH_SCOPES, redirect_uri=REDIRECT_URI, prompt="select_account")
    session["flow"] = flow
    return redirect(flow["auth_uri"])


@app.route("/auth/callback")
def callback():
    try:
        result = msal_app().acquire_token_by_auth_code_flow(session.pop("flow", {}), request.args)
    except ValueError:  # state mismatch or replayed callback
        return redirect(url_for("index"))
    if "error" in result:
        return render_template("error.html", error=result.get("error"), detail=result.get("error_description")), 400

    claims = result["id_token_claims"]
    manager_oid, manager_name = None, None
    # OAuth 2.0 in action: the ACCESS token is for Microsoft Graph, not for this app.
    # Used once here, then discarded; it is never stored in the session.
    r = requests.get("https://graph.microsoft.com/v1.0/me/manager?$select=id,displayName",
                     headers={"Authorization": f"Bearer {result['access_token']}"}, timeout=10)
    if r.ok:
        manager_oid, manager_name = r.json().get("id"), r.json().get("displayName")

    session["user"] = {
        "oid": claims.get("oid"), "name": claims.get("name"), "upn": claims.get("preferred_username"),
        "roles": claims.get("roles", []), "manager_oid": manager_oid, "manager_name": manager_name,
    }
    # Keep a trimmed copy of the ID token claims for the token inspector page.
    keep = ("aud", "iss", "iat", "exp", "name", "preferred_username", "oid", "tid", "roles", "amr", "acr", "ver")
    session["id_token_claims"] = {k: claims[k] for k in keep if k in claims}
    audit("sign-in", None, "Success", f"roles={','.join(claims.get('roles', [])) or 'none'}")
    return redirect(url_for("index"))


@app.route("/logout")
def logout():
    session.clear()
    base = request.host_url.rstrip("/")
    return redirect(f"{AUTHORITY}/oauth2/v2.0/logout?post_logout_redirect_uri={base}/")


# --------------------------------------------------------------------------- pages
@app.route("/")
def index():
    if "user" not in session:
        return render_template("welcome.html")
    return render_template("home.html", role_info=ROLE_INFO, my_roles=roles())


@app.route("/token")
@login_required
def token():
    return render_template("token.html", claims=session.get("id_token_claims", {}))


@app.route("/claims", methods=["GET", "POST"])
@login_required
def my_claims():
    require_role(ROLE_SUBMIT)
    u = session["user"]
    if request.method == "POST":
        try:
            amount = round(float(request.form["amount"]), 2)
        except (KeyError, ValueError):
            amount = 0
        description = request.form.get("description", "").strip()[:200]
        if amount <= 0 or not description:
            flash("Enter a positive amount and a description.", "error")
        elif not u.get("manager_oid"):
            flash("You have no manager in Entra ID, so there's nobody to approve your claim.", "error")
            audit("submit", None, "Denied", "No manager")
        else:
            cid = "EXP-" + uuid.uuid4().hex[:6].upper()
            db().execute("""INSERT INTO claims (id, created, submitter_oid, submitter_name, manager_oid, amount,
                            currency, category, description, status) VALUES (?,?,?,?,?,?,?,?,?,?)""",
                         (cid, now(), u["oid"], u["name"], u["manager_oid"], amount,
                          request.form.get("currency", "USD"), request.form.get("category", "Other"), description, "Submitted"))
            db().commit()
            audit("submit", cid, "Success", f"{amount} {request.form.get('currency', 'USD')}")
            flash(f"Claim {cid} submitted to {u.get('manager_name')} for approval.", "ok")
        return redirect(url_for("my_claims"))
    rows = db().execute("SELECT * FROM claims WHERE submitter_oid=? ORDER BY created DESC", (u["oid"],)).fetchall()
    return render_template("claims.html", claims=rows)


@app.route("/approvals")
@login_required
def approvals():
    require_role(ROLE_APPROVE)
    rows = db().execute("SELECT * FROM claims WHERE manager_oid=? AND status='Submitted' ORDER BY created",
                        (session["user"]["oid"],)).fetchall()
    return render_template("queue.html", title="Team approvals", claims=rows, action="approve",
                           note="Claims from people who report to you in Entra ID.")


@app.route("/finance")
@login_required
def finance():
    if not roles() & {ROLE_REVIEW, ROLE_PAY}:
        require_role(ROLE_REVIEW)
    review = db().execute("SELECT * FROM claims WHERE status='Approved' ORDER BY created").fetchall() if ROLE_REVIEW in roles() else []
    pay = db().execute("SELECT * FROM claims WHERE status='Reviewed' ORDER BY created").fetchall() if ROLE_PAY in roles() else []
    return render_template("finance.html", review=review, pay=pay)


def check_action(action, c, me):
    """Return (allowed, reason). These rules are the app-level separation of duties."""
    if action == "approve":
        if ROLE_APPROVE not in roles():
            return False, "No Expenses.Approve role"
        if c["status"] != "Submitted":
            return False, f"Claim is {c['status']}, not Submitted"
        if c["submitter_oid"] == me:
            return False, "You can't approve your own claim"
        if c["manager_oid"] != me:
            return False, "Only the submitter's manager can approve"
    elif action == "review":
        if ROLE_REVIEW not in roles():
            return False, "No Expenses.Review role"
        if c["status"] != "Approved":
            return False, f"Claim is {c['status']}, not Approved"
        if me in (c["submitter_oid"], c["approved_by_oid"]):
            return False, "You can't review a claim you submitted or approved"
    elif action == "pay":
        if ROLE_PAY not in roles():
            return False, "No Expenses.Pay role"
        if c["status"] != "Reviewed":
            return False, f"Claim is {c['status']}, not Reviewed"
        if c["submitter_oid"] == me:
            return False, "You can't pay your own claim"
        if c["approved_by_oid"] == me:
            return False, "SOD-01: you approved this claim, so you can't release its payment (EXC-001 compensating control)"
        if c["reviewed_by_oid"] == me:
            return False, "Four-eyes rule: the reviewer can't also release the payment"
    elif action == "reject":
        allowed = (ROLE_APPROVE in roles() and c["status"] == "Submitted" and c["manager_oid"] == me) or \
                  (ROLE_REVIEW in roles() and c["status"] == "Approved" and me != c["submitter_oid"])
        return (True, "") if allowed else (False, "You can't reject this claim at its current stage")
    else:
        return False, "Unknown action"
    return True, ""


@app.route("/claims/<cid>/<action>", methods=["POST"])
@login_required
def act(cid, action):
    me, name = session["user"]["oid"], session["user"]["name"]
    c = db().execute("SELECT * FROM claims WHERE id=?", (cid,)).fetchone()
    if c is None:
        abort(404)
    ok, reason = check_action(action, c, me)
    if not ok:
        audit(action, cid, "Denied", reason)
        flash(f"{cid}: {reason}.", "error")
        return redirect(request.referrer or url_for("index"))
    ts = now()
    if action == "approve":
        db().execute("UPDATE claims SET status='Approved', approved_by_oid=?, approved_by_name=?, approved_at=? WHERE id=?", (me, name, ts, cid))
    elif action == "review":
        db().execute("UPDATE claims SET status='Reviewed', reviewed_by_oid=?, reviewed_by_name=?, reviewed_at=? WHERE id=?", (me, name, ts, cid))
    elif action == "pay":
        db().execute("UPDATE claims SET status='Paid', paid_by_oid=?, paid_by_name=?, paid_at=? WHERE id=?", (me, name, ts, cid))
    elif action == "reject":
        db().execute("UPDATE claims SET status='Rejected' WHERE id=?", (cid,))
    db().commit()
    audit(action, cid, "Success")
    flash(f"{cid}: {action} recorded.", "ok")
    return redirect(request.referrer or url_for("index"))


@app.route("/audit")
@login_required
def audit_view():
    require_role(ROLE_AUDIT)
    claims = db().execute("SELECT * FROM claims ORDER BY created DESC").fetchall()
    events = db().execute("SELECT * FROM audit ORDER BY id DESC LIMIT 200").fetchall()
    return render_template("audit.html", claims=claims, events=events)


@app.errorhandler(403)
def forbidden(e):
    return render_template("error.html", error="403 Forbidden", detail=e.description), 403


with app.app_context():
    init_db()

if __name__ == "__main__":
    app.run(host="localhost", port=5000, debug=False)
