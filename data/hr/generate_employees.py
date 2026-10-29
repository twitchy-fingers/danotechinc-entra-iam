#!/usr/bin/env python3
"""
generate_employees.py - builds the DanotechInc HR master file (employees.csv).

The HR system is the authoritative source of identity for DanotechInc. This
script simulates that system's export so every phase works from the same
200 people. It is deterministic (fixed seed): re-running it produces the
same file, so the dataset never drifts between phases.

Usage:
    python generate_employees.py            # writes employees.csv + departments.csv
"""
import csv
import random
import unicodedata
from collections import defaultdict
from datetime import date, timedelta

SEED = 20261027
TENANT_DOMAIN = "danotechinc.onmicrosoft.com"
COMPANY = "DanotechInc"
random.seed(SEED)

# --------------------------------------------------------------------------
# Offices
# --------------------------------------------------------------------------
OFFICES = {
    "ATL": {"office": "Atlanta HQ", "city": "Atlanta", "country": "United States", "usage": "US"},
    "LON": {"office": "London", "city": "London", "country": "United Kingdom", "usage": "GB"},
    "LOS": {"office": "Lagos", "city": "Lagos", "country": "Nigeria", "usage": "NG"},
    "ACC": {"office": "Accra", "city": "Accra", "country": "Ghana", "usage": "GH"},
    "MEX": {"office": "Mexico City", "city": "Mexico City", "country": "Mexico", "usage": "MX"},
    "RMT": {"office": "Remote - US", "city": "Remote", "country": "United States", "usage": "US"},
}

# Which name origins appear in which office (weights). Diaspora is realistic:
# a Nigerian-named engineer in Atlanta, a Ghanaian-named analyst in London.
OFFICE_NAME_MIX = {
    "ATL": {"US": 70, "NG": 9, "GH": 6, "MX": 7, "IN": 4, "KE": 2, "UK": 2},
    "LON": {"UK": 65, "NG": 12, "GH": 8, "IN": 10, "KE": 3, "US": 2},
    "LOS": {"NG": 96, "GH": 4},
    "ACC": {"GH": 94, "NG": 6},
    "MEX": {"MX": 95, "US": 5},
    "RMT": {"US": 55, "MX": 15, "NG": 12, "GH": 6, "IN": 8, "KE": 4},
}

NAMES = {
    "NG": {
        "first": ["Chinedu", "Ngozi", "Oluwaseun", "Funmilayo", "Emeka", "Chiamaka", "Babatunde",
                  "Yetunde", "Ifeanyi", "Amaka", "Segun", "Bukola", "Obinna", "Zainab", "Ibrahim",
                  "Aisha", "Tobiloba", "Kelechi", "Uchenna", "Damilola", "Musa", "Halima", "Femi",
                  "Temitope", "Nkechi", "Olumide", "Chidinma", "Tochukwu", "Ebere", "Adebola"],
        "last": ["Okafor", "Adeyemi", "Nwosu", "Balogun", "Okonkwo", "Eze", "Abubakar", "Bello",
                 "Okoro", "Adebayo", "Ogunleye", "Chukwu", "Ibekwe", "Danjuma", "Olawale", "Ugwu",
                 "Afolabi", "Lawal", "Onyeka", "Obi", "Akinola", "Nnaji", "Uzor", "Ojo"],
    },
    "GH": {
        "first": ["Kwame", "Kofi", "Ama", "Akosua", "Yaw", "Abena", "Kwabena", "Efua", "Kojo", "Esi",
                  "Kwesi", "Adwoa", "Nii", "Naa", "Yaa", "Fiifi", "Akua", "Selorm", "Edem", "Afia",
                  "Kobina", "Araba", "Elikem", "Dzifa"],
        "last": ["Mensah", "Asante", "Owusu", "Boateng", "Appiah", "Osei", "Agyeman", "Darko", "Ofori",
                 "Amoah", "Quaye", "Tetteh", "Addo", "Antwi", "Sarpong", "Ansah", "Frimpong", "Asamoah",
                 "Badu", "Kyei"],
    },
    "US": {
        "first": ["James", "Ashley", "Michael", "Jessica", "Tyler", "Brittany", "Jamal", "Keisha",
                  "Brandon", "Megan", "Andre", "Lauren", "Kevin", "Danielle", "Marcus", "Taylor",
                  "Jordan", "Hannah", "Darnell", "Kayla", "Ryan", "Nicole", "Malik", "Courtney",
                  "Austin", "Brianna", "Derrick", "Madison"],
        "last": ["Johnson", "Williams", "Brown", "Davis", "Miller", "Wilson", "Anderson", "Jackson",
                 "Harris", "Robinson", "Walker", "Young", "King", "Wright", "Scott", "Green", "Baker",
                 "Carter", "Mitchell", "Parker", "Collins", "Washington", "Brooks", "Reed", "Coleman",
                 "Hayes"],
    },
    "MX": {
        "first": ["José", "María", "Alejandro", "Guadalupe", "Luis", "Fernanda", "Carlos", "Ximena",
                  "Miguel", "Valeria", "Javier", "Sofía", "Ricardo", "Daniela", "Andrés", "Camila",
                  "Eduardo", "Itzel", "Raúl", "Mariana", "Emiliano", "Renata", "Santiago", "Paola"],
        "last": ["Hernández", "García", "Martínez", "López", "González", "Rodríguez", "Pérez",
                 "Sánchez", "Ramírez", "Flores", "Torres", "Rivera", "Gómez", "Díaz", "Cruz",
                 "Morales", "Reyes", "Ortiz", "Gutiérrez", "Castillo", "Vargas", "Mendoza"],
    },
    "UK": {
        "first": ["Oliver", "Amelia", "Harry", "Olivia", "George", "Isla", "Jack", "Emily", "Charlie",
                  "Sophie", "Thomas", "Grace", "William", "Poppy", "Alfie", "Freya", "Rhys", "Siobhan",
                  "Callum", "Niamh", "Harriet", "Rory"],
        "last": ["Smith", "Jones", "Taylor", "Evans", "Thomas", "Roberts", "Hughes", "Lewis", "Edwards",
                 "Wright", "Walsh", "Clarke", "Murphy", "Campbell", "Kelly", "Price", "Morgan",
                 "Bennett", "Shaw", "Fletcher", "Holmes", "Turner"],
    },
    "IN": {
        "first": ["Priya", "Arjun", "Ananya", "Rohan", "Kavya", "Vikram", "Meera", "Aditya", "Neha", "Sanjay"],
        "last": ["Sharma", "Patel", "Iyer", "Reddy", "Nair", "Gupta", "Menon", "Kapoor", "Khan", "Desai"],
    },
    "KE": {
        "first": ["Wanjiru", "Otieno", "Achieng", "Kamau", "Njeri", "Mwangi", "Akinyi", "Kipchoge"],
        "last": ["Kamau", "Odhiambo", "Wanjiku", "Mutua", "Kariuki", "Omondi", "Njoroge", "Chebet"],
    },
}

# --------------------------------------------------------------------------
# Departments
# --------------------------------------------------------------------------
DEPARTMENTS = [
    # code, name, cost centre, division
    ("EXE", "Executive Office", "CC1000", "Corporate"),
    ("FIN", "Finance", "CC2000", "Corporate"),
    ("HR", "Human Resources", "CC2100", "Corporate"),
    ("LEG", "Legal & Compliance", "CC2200", "Corporate"),
    ("OPS", "Operations", "CC2300", "Corporate"),
    ("MKT", "Marketing", "CC3000", "Go-To-Market"),
    ("SAL", "Sales", "CC3100", "Go-To-Market"),
    ("CS", "Customer Success", "CC3200", "Go-To-Market"),
    ("ENG", "Engineering", "CC4000", "Technology"),
    ("IT", "Information Technology", "CC5000", "Technology"),
    ("SEC", "Information Security", "CC5100", "Technology"),
]
DEPT = {d[0]: d for d in DEPARTMENTS}

# --------------------------------------------------------------------------
# Named key personas. These people are referenced by name across phases
# (RACI, approvers, admins, reviewers), so they are fixed, not random.
# key, first, last, title, job code, level, dept, office, reports_to_key, hire date
# --------------------------------------------------------------------------
KEY_PEOPLE = [
    ("CEO", "Daniel", "Opara", "Chief Executive Officer", "EXE-CEO", "L10", "EXE", "ATL", None, "2015-03-02"),
    ("COS", "Sophie", "Bennett", "Chief of Staff", "EXE-COS", "L8", "EXE", "LON", "CEO", "2018-06-11"),
    ("EA", "Keisha", "Morgan", "Executive Assistant to the CEO", "EXE-EA", "L4", "EXE", "ATL", "CEO", "2019-09-16"),
    ("CFO", "Kwame", "Asante", "Chief Financial Officer", "FIN-CFO", "L9", "FIN", "ACC", "CEO", "2016-01-18"),
    ("CHRO", "Folasade", "Adeyemi", "Chief People Officer", "HR-CHRO", "L9", "HR", "ATL", "CEO", "2016-08-01"),
    ("GC", "Akosua", "Boateng", "General Counsel", "LEG-GC", "L9", "LEG", "ACC", "CEO", "2017-04-03"),
    ("COO", "Jamal", "Washington", "VP Operations", "OPS-VP", "L8", "OPS", "ATL", "CEO", "2017-02-13"),
    ("CMO", "Charlotte", "Davies", "Chief Marketing Officer", "MKT-CMO", "L9", "MKT", "LON", "CEO", "2018-01-08"),
    ("CRO", "Marcus", "Thompson", "Chief Revenue Officer", "SAL-CRO", "L9", "SAL", "ATL", "CEO", "2016-05-23"),
    ("VPCS", "Lucía", "Herrera", "VP Customer Success", "CS-VP", "L8", "CS", "MEX", "CRO", "2018-10-01"),
    ("CTO", "Valeria", "Mendoza", "Chief Technology Officer", "ENG-CTO", "L9", "ENG", "MEX", "CEO", "2015-07-06"),
    ("CIO", "Chukwuemeka", "Eze", "Chief Information Officer", "IT-CIO", "L9", "IT", "LOS", "CEO", "2016-03-14"),
    ("CISO", "Oliver", "Hughes", "Chief Information Security Officer", "SEC-CISO", "L9", "SEC", "LON", "CEO", "2019-02-04"),
    # Identity & Access Management team (IT) - the people building this project
    ("IAMMGR", "Adaeze", "Nwosu", "IAM Manager", "IT-IAM-MGR", "L7", "IT", "LOS", "CIO", "2019-11-04"),
    ("IAM1", "Kofi", "Owusu", "Senior IAM Engineer", "IT-IAM-ENG", "L6", "IT", "ACC", "IAMMGR", "2020-05-18"),
    ("IAM2", "Diego", "Ramírez", "IAM Engineer", "IT-IAM-ENG", "L5", "IT", "MEX", "IAMMGR", "2022-03-07"),
    ("IAM3", "Emily", "Carter", "IAM Engineer", "IT-IAM-ENG", "L5", "IT", "ATL", "IAMMGR", "2023-01-09"),
    ("INFRAMGR", "Babatunde", "Bakare", "Cloud & Infrastructure Manager", "IT-INF-MGR", "L7", "IT", "LOS", "CIO", "2018-07-23"),
    ("SDLEAD", "Grace", "Robinson", "Service Desk Lead", "IT-SD-LEAD", "L6", "IT", "ATL", "CIO", "2019-04-15"),
    # Security leadership
    ("SOCMGR", "Priya", "Sharma", "Security Operations Manager", "SEC-SOC-MGR", "L7", "SEC", "LON", "CISO", "2020-09-14"),
    ("GRCMGR", "Nana", "Agyeman", "GRC Manager", "SEC-GRC-MGR", "L7", "SEC", "ACC", "CISO", "2020-02-03"),
    # Department second-line managers referenced in later phases
    ("FINCTRL", "Rachel", "Okafor", "Financial Controller", "FIN-CTRL", "L7", "FIN", "ATL", "CFO", "2018-03-19"),
    ("HRBPMGR", "Tunde", "Afolabi", "HR Operations Manager", "HR-OPS-MGR", "L7", "HR", "LOS", "CHRO", "2019-06-03"),
    ("SALDIR_AM", "Brandon", "Collins", "Director of Sales - Americas", "SAL-DIR", "L7", "SAL", "ATL", "CRO", "2018-08-20"),
    ("SALDIR_EM", "Harriet", "Walsh", "Director of Sales - EMEA", "SAL-DIR", "L7", "SAL", "LON", "CRO", "2019-01-14"),
    ("SALOPS", "Fernanda", "Castillo", "Sales Operations Manager", "SAL-OPS-MGR", "L6", "SAL", "MEX", "CRO", "2020-10-05"),
    ("MKTDIR", "Ngozi", "Balogun", "Director of Digital Marketing", "MKT-DIR", "L7", "MKT", "LON", "CMO", "2019-05-27"),
    ("ENGDIR_PLAT", "Arjun", "Iyer", "Director of Platform Engineering", "ENG-DIR", "L8", "ENG", "ATL", "CTO", "2017-11-06"),
    ("ENGDIR_PROD", "Yaw", "Darko", "Director of Product Engineering", "ENG-DIR", "L8", "ENG", "ACC", "CTO", "2018-02-26"),
    ("EMGR_DEVOPS", "Carlos", "Gutiérrez", "Engineering Manager - DevOps & SRE", "ENG-EM", "L7", "ENG", "MEX", "ENGDIR_PLAT", "2019-08-12"),
    ("EMGR_BACK", "Oluwaseun", "Ogunleye", "Engineering Manager - Backend", "ENG-EM", "L7", "ENG", "LOS", "ENGDIR_PROD", "2019-03-25"),
    ("EMGR_FRONT", "Mariana", "Torres", "Engineering Manager - Frontend", "ENG-EM", "L7", "ENG", "MEX", "ENGDIR_PROD", "2020-06-08"),
    ("EMGR_DATA", "Siobhan", "Kelly", "Engineering Manager - Data & AI", "ENG-EM", "L7", "ENG", "LON", "ENGDIR_PLAT", "2021-01-11"),
    ("EMGR_QA", "Efua", "Tetteh", "Engineering Manager - Quality", "ENG-EM", "L7", "ENG", "ACC", "ENGDIR_PROD", "2020-11-16"),
]

# --------------------------------------------------------------------------
# Generated roles: (job title, job code, level, family, dept, count,
#                   reports_to_key, office weights)
# --------------------------------------------------------------------------
ROLES = [
    # Finance (18 total incl. CFO + controller)
    ("Senior Accountant", "FIN-ACCT-SR", "L5", "Finance", "FIN", 3, "FINCTRL", {"ATL": 2, "ACC": 3}),
    ("Accountant", "FIN-ACCT", "L4", "Finance", "FIN", 4, "FINCTRL", {"ATL": 2, "ACC": 3}),
    ("Accounts Payable Specialist", "FIN-AP", "L3", "Finance", "FIN", 4, "FINCTRL", {"ACC": 3, "LOS": 1}),
    ("Financial Analyst", "FIN-FPA", "L4", "Finance", "FIN", 3, "CFO", {"ATL": 2, "LON": 1}),
    ("Payroll Specialist", "FIN-PAY", "L4", "Finance", "FIN", 2, "FINCTRL", {"ATL": 1, "ACC": 1}),
    # HR (12 incl. CHRO + ops mgr)
    ("HR Business Partner", "HR-HRBP", "L5", "People", "HR", 4, "CHRO", {"ATL": 2, "LON": 1, "LOS": 1}),
    ("HR Generalist", "HR-GEN", "L4", "People", "HR", 3, "HRBPMGR", {"LOS": 2, "ACC": 1, "MEX": 1}),
    ("Talent Acquisition Specialist", "HR-TA", "L4", "People", "HR", 2, "HRBPMGR", {"ATL": 1, "LOS": 1}),
    ("HRIS Analyst", "HR-HRIS", "L5", "People", "HR", 1, "HRBPMGR", {"LOS": 1}),
    # Legal & Compliance (7 incl. GC)
    ("Corporate Counsel", "LEG-CNSL", "L6", "Legal", "LEG", 2, "GC", {"ATL": 1, "LON": 1}),
    ("Compliance Analyst", "LEG-COMP", "L4", "Legal", "LEG", 2, "GC", {"ACC": 1, "ATL": 1}),
    ("Privacy Officer", "LEG-PRIV", "L6", "Legal", "LEG", 1, "GC", {"LON": 1}),
    ("Paralegal", "LEG-PARA", "L3", "Legal", "LEG", 1, "GC", {"ATL": 1}),
    # Operations (10 incl. VP)
    ("Business Operations Analyst", "OPS-BIZ", "L4", "Operations", "OPS", 3, "COO", {"ATL": 2, "RMT": 1}),
    ("Procurement Specialist", "OPS-PROC", "L4", "Operations", "OPS", 2, "COO", {"ATL": 1, "LOS": 1}),
    ("Facilities Coordinator", "OPS-FAC", "L3", "Operations", "OPS", 3, "COO", {"ATL": 1, "LON": 1, "LOS": 1, "ACC": 1, "MEX": 1}),
    ("Vendor Manager", "OPS-VEND", "L5", "Operations", "OPS", 1, "COO", {"ATL": 1}),
    # Marketing (22 incl. CMO + director)
    ("Marketing Manager", "MKT-MGR", "L6", "Marketing", "MKT", 3, "MKTDIR", {"LON": 2, "ATL": 1}),
    ("Content Strategist", "MKT-CONT", "L4", "Marketing", "MKT", 4, "MKTDIR", {"LON": 2, "ATL": 1, "RMT": 1}),
    ("Digital Marketing Specialist", "MKT-DIG", "L4", "Marketing", "MKT", 4, "MKTDIR", {"LON": 1, "LOS": 1, "MEX": 1, "ATL": 1}),
    ("Graphic Designer", "MKT-DES", "L4", "Marketing", "MKT", 3, "CMO", {"LON": 1, "MEX": 1, "LOS": 1}),
    ("Web Content Manager", "MKT-WEB", "L5", "Marketing", "MKT", 2, "MKTDIR", {"LON": 1, "ATL": 1}),
    ("Marketing Analyst", "MKT-ANL", "L4", "Marketing", "MKT", 2, "CMO", {"ATL": 1, "ACC": 1}),
    ("Events Coordinator", "MKT-EVT", "L3", "Marketing", "MKT", 2, "CMO", {"ATL": 1, "LON": 1}),
    # Sales (32 incl. CRO + 2 directors + ops mgr)
    ("Account Executive", "SAL-AE", "L5", "Sales", "SAL", 10, "SALDIR_AM", {"ATL": 5, "RMT": 3, "MEX": 2}),
    ("Account Executive", "SAL-AE", "L5", "Sales", "SAL", 6, "SALDIR_EM", {"LON": 3, "LOS": 2, "ACC": 1}),
    ("Sales Development Representative", "SAL-SDR", "L3", "Sales", "SAL", 6, "SALDIR_AM", {"ATL": 3, "MEX": 2, "RMT": 1}),
    ("Sales Engineer", "SAL-SE", "L6", "Sales", "SAL", 3, "CRO", {"ATL": 1, "LON": 1, "MEX": 1}),
    ("Sales Operations Analyst", "SAL-OPS", "L4", "Sales", "SAL", 3, "SALOPS", {"MEX": 2, "ATL": 1}),
    # Customer Success (16 incl. VP)
    ("Customer Success Manager", "CS-CSM", "L5", "Customer Success", "CS", 7, "VPCS", {"MEX": 3, "ATL": 2, "LON": 1, "LOS": 1}),
    ("Support Engineer", "CS-SUP", "L4", "Customer Success", "CS", 6, "VPCS", {"MEX": 2, "LOS": 2, "ACC": 1, "RMT": 1}),
    ("Implementation Consultant", "CS-IMP", "L5", "Customer Success", "CS", 2, "VPCS", {"ATL": 1, "LON": 1}),
    # Engineering (54 incl. CTO + 2 directors + 5 EMs)
    ("Senior Software Engineer", "ENG-SWE-SR", "L6", "Engineering", "ENG", 6, "EMGR_BACK", {"LOS": 3, "ATL": 1, "RMT": 2}),
    ("Software Engineer", "ENG-SWE", "L5", "Engineering", "ENG", 6, "EMGR_BACK", {"LOS": 3, "ACC": 2, "RMT": 1}),
    ("Senior Software Engineer", "ENG-SWE-SR", "L6", "Engineering", "ENG", 3, "EMGR_FRONT", {"MEX": 2, "LON": 1}),
    ("Software Engineer", "ENG-SWE", "L5", "Engineering", "ENG", 5, "EMGR_FRONT", {"MEX": 3, "ATL": 1, "RMT": 1}),
    ("DevOps Engineer", "ENG-DEVOPS", "L5", "Engineering", "ENG", 4, "EMGR_DEVOPS", {"MEX": 2, "ATL": 1, "LOS": 1}),
    ("Site Reliability Engineer", "ENG-SRE", "L6", "Engineering", "ENG", 3, "EMGR_DEVOPS", {"ATL": 1, "LON": 1, "RMT": 1}),
    ("Data Engineer", "ENG-DATA", "L5", "Engineering", "ENG", 4, "EMGR_DATA", {"LON": 2, "ACC": 1, "LOS": 1}),
    ("Machine Learning Engineer", "ENG-ML", "L6", "Engineering", "ENG", 3, "EMGR_DATA", {"LON": 1, "ATL": 1, "RMT": 1}),
    ("QA Engineer", "ENG-QA", "L4", "Engineering", "ENG", 5, "EMGR_QA", {"ACC": 3, "LOS": 1, "MEX": 1}),
    ("Product Manager", "ENG-PM", "L6", "Product", "ENG", 4, "CTO", {"ATL": 2, "LON": 1, "MEX": 1}),
    ("UX Designer", "ENG-UX", "L5", "Product", "ENG", 3, "ENGDIR_PROD", {"MEX": 1, "LON": 1, "ATL": 1}),
    # IT (16 incl. CIO + IAM team 4 + infra mgr + SD lead)
    ("Cloud Engineer", "IT-CLOUD", "L5", "IT", "IT", 3, "INFRAMGR", {"LOS": 1, "ATL": 1, "MEX": 1}),
    ("Systems Administrator", "IT-SYSADM", "L4", "IT", "IT", 2, "INFRAMGR", {"ACC": 1, "LON": 1}),
    ("Service Desk Analyst", "IT-SD", "L3", "IT", "IT", 4, "SDLEAD", {"ATL": 1, "LOS": 1, "LON": 1, "MEX": 1}),
    # Security (10 incl. CISO + SOC mgr + GRC mgr)
    ("SOC Analyst", "SEC-SOC", "L4", "Security", "SEC", 3, "SOCMGR", {"LON": 1, "LOS": 1, "ATL": 1}),
    ("Detection Engineer", "SEC-DET", "L6", "Security", "SEC", 1, "SOCMGR", {"LON": 1}),
    ("Vulnerability Management Engineer", "SEC-VULN", "L5", "Security", "SEC", 1, "SOCMGR", {"MEX": 1}),
    ("GRC Analyst", "SEC-GRC", "L4", "Security", "SEC", 2, "GRCMGR", {"ACC": 1, "ATL": 1}),
]

# --------------------------------------------------------------------------
# Lifecycle scenarios baked into the HR feed (used heavily in Phase 04).
# job codes eligible for each, and how many.
# --------------------------------------------------------------------------
CONTRACTOR_RULES = [("ENG-SWE", 4), ("ENG-QA", 2), ("IT-SD", 1), ("MKT-DES", 2), ("MKT-CONT", 1),
                    ("CS-SUP", 1), ("SEC-SOC", 1)]
INTERN_RULES = [("ENG-SWE", 2), ("MKT-DIG", 1), ("FIN-ACCT", 1)]
PREHIRE_RULES = [("SAL-AE", 2), ("ENG-SWE-SR", 1), ("CS-CSM", 1), ("HR-GEN", 1), ("ENG-DATA", 1)]
LEAVER_RULES = [("SAL-SDR", 1), ("MKT-CONT", 1), ("ENG-SWE", 1), ("FIN-AP", 1)]

AS_OF = date(2026, 10, 27)


def ascii_slug(s: str) -> str:
    """Strip accents and characters not allowed in a UPN prefix."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(ch for ch in s.lower() if ch.isalnum())


def weighted(choices: dict) -> str:
    keys = list(choices)
    return random.choices(keys, weights=[choices[k] for k in keys])[0]


def random_hire_date(level: str) -> date:
    # More senior people tend to have longer tenure.
    lvl = int(level[1:])
    start = date(2016, 1, 1) if lvl >= 6 else date(2019, 1, 1)
    end = date(2026, 9, 30)
    d = start + timedelta(days=random.randint(0, (end - start).days))
    while d.weekday() != 0:  # start dates are Mondays
        d += timedelta(days=1)
    return d


def main():
    used_names, used_upns = set(), set()
    rows, key_to_ids = [], defaultdict(list)

    def make_upn(first, last):
        base = f"{ascii_slug(first)}.{ascii_slug(last)}"
        upn, n = base, 2
        while upn in used_upns:
            upn, n = f"{base}{n}", n + 1
        used_upns.add(upn)
        return upn

    def add(first, last, title, code, level, family, dept, office, mgr_key, hire, key=None):
        eid = f"DT{1000 + len(rows) + 1:05d}"
        upn = make_upn(first, last)
        o = OFFICES[office]
        d = DEPT[dept]
        rows.append({
            "EmployeeId": eid, "FirstName": first, "LastName": last,
            "DisplayName": f"{first} {last}",
            "UserPrincipalName": f"{upn}@{TENANT_DOMAIN}", "MailNickname": upn,
            "JobTitle": title, "JobCode": code, "JobLevel": level, "JobFamily": family,
            "Department": d[1], "DepartmentCode": d[0], "CostCenter": d[2], "Division": d[3],
            "_mgr_key": mgr_key, "ManagerEmployeeId": "", "ManagerUPN": "",
            "CompanyName": COMPANY, "Office": o["office"], "City": o["city"],
            "Country": o["country"], "UsageLocation": o["usage"],
            "EmployeeType": "Employee", "EmploymentStatus": "Active",
            "HireDate": hire, "EndDate": "",
        })
        used_names.add((first, last))
        if key:
            key_to_ids[key].append(eid)
        return eid

    family_of = {"EXE": "Executive", "FIN": "Finance", "HR": "People", "LEG": "Legal", "OPS": "Operations",
                 "MKT": "Marketing", "SAL": "Sales", "CS": "Customer Success", "ENG": "Engineering",
                 "IT": "IT", "SEC": "Security"}

    for (key, first, last, title, code, level, dept, office, mgr, hire) in KEY_PEOPLE:
        add(first, last, title, code, level, family_of[dept], dept, office, mgr, hire, key=key)

    for (title, code, level, family, dept, count, mgr, office_w) in ROLES:
        for _ in range(count):
            office = weighted(office_w)
            origin = weighted(OFFICE_NAME_MIX[office])
            for _attempt in range(50):
                first = random.choice(NAMES[origin]["first"])
                last = random.choice(NAMES[origin]["last"])
                if (first, last) not in used_names and first != last:
                    break
            add(first, last, title, code, level, family, dept, office, mgr,
                random_hire_date(level).isoformat())

    # Resolve managers.
    by_id = {r["EmployeeId"]: r for r in rows}
    for r in rows:
        if r["_mgr_key"]:
            mid = key_to_ids[r["_mgr_key"]][0]
            r["ManagerEmployeeId"] = mid
            r["ManagerUPN"] = by_id[mid]["UserPrincipalName"]

    # Apply lifecycle scenarios to generated (non-key) staff only.
    key_ids = {i for ids in key_to_ids.values() for i in ids}
    pool = [r for r in rows if r["EmployeeId"] not in key_ids]
    taken = set()

    def pick(code, n):
        cands = [r for r in pool if r["JobCode"] == code and r["EmployeeId"] not in taken]
        chosen = random.sample(cands, min(n, len(cands)))
        taken.update(c["EmployeeId"] for c in chosen)
        return chosen

    for code, n in CONTRACTOR_RULES:
        for r in pick(code, n):
            r["EmployeeType"] = "Contractor"
            r["JobTitle"] = f"{r['JobTitle']} (Contract)"
            hire = date(2026, random.randint(1, 8), 1)
            r["HireDate"] = hire.isoformat()
            r["EndDate"] = date(2027, random.randint(1, 6), 28).isoformat()
    for code, n in INTERN_RULES:
        for r in pick(code, n):
            r["EmployeeType"] = "Intern"
            r["JobTitle"] = f"{r['JobTitle']} Intern"
            r["JobLevel"] = "L1"
            r["HireDate"] = "2026-06-01"
            r["EndDate"] = "2026-12-18"
    prehire_dates = ["2026-11-02", "2026-11-09", "2026-11-16", "2026-11-30", "2026-12-07", "2027-01-04"]
    for (code, n), _ in zip(PREHIRE_RULES, range(99)):
        for r in pick(code, n):
            r["EmploymentStatus"] = "PreHire"
            r["HireDate"] = prehire_dates.pop(0)
    leaver_dates = ["2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27"]
    for code, n in LEAVER_RULES:
        for r in pick(code, n):
            r["EndDate"] = leaver_dates.pop(0)  # Active today, termination scheduled

    fields = [k for k in rows[0] if not k.startswith("_")]
    with open("employees.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in fields})

    with open("departments.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["DepartmentCode", "Department", "CostCenter", "Division", "Headcount", "DepartmentHeadUPN"])
        heads = {"EXE": "CEO", "FIN": "CFO", "HR": "CHRO", "LEG": "GC", "OPS": "COO", "MKT": "CMO",
                 "SAL": "CRO", "CS": "VPCS", "ENG": "CTO", "IT": "CIO", "SEC": "CISO"}
        for code, name, cc, div in DEPARTMENTS:
            hc = sum(1 for r in rows if r["DepartmentCode"] == code)
            head = by_id[key_to_ids[heads[code]][0]]["UserPrincipalName"]
            w.writerow([code, name, cc, div, hc, head])

    print(f"Wrote {len(rows)} employees")


if __name__ == "__main__":
    main()
