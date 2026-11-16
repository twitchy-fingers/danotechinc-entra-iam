<?php
/**
 * Plugin Name: DanotechInc Entra ID role mapping
 * Description: Sets each WordPress user's role from the Entra ID app roles in their ID token, on every sign-in.
 * Version:     1.0
 *
 * Why this exists
 *   The "OpenID Connect Generic Client" plugin signs people in with Entra ID but doesn't map app roles.
 *   DanotechInc's access model says WordPress access comes ONLY from Entra ID (policy AC-01):
 *     WordPress.Admin  -> administrator   (GRP-ROLE-PIM-WP-ADMIN: just-in-time through PIM)
 *     WordPress.Editor -> editor          (GRP-DYN-JOB-MKT-WEB)
 *     WordPress.Author -> author          (GRP-DYN-JOB-MKT)
 *   The highest role in the token wins. A token with none of them gets "subscriber" (no publishing).
 *
 *   Re-applied on EVERY sign-in, so access also shrinks: when Ngozi's PIM activation ends, her next
 *   sign-in turns her admin account back into a subscriber. Nobody edits roles inside WordPress.
 *
 * Where the roles come from
 *   The OIDC plugin stores the token response it received from Entra ID's token endpoint in user
 *   meta. That token came over a direct TLS back-channel from Entra ID, so this plugin only decodes
 *   the payload; it doesn't need to re-check the signature.
 *
 * Mounted read-only by docker-compose.yml. "mu" (must-use) plugins can't be disabled from wp-admin.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

const DANOTECH_ROLE_MAP = array(
	'WordPress.Admin'  => 'administrator',
	'WordPress.Editor' => 'editor',
	'WordPress.Author' => 'author',
);
const DANOTECH_TOKEN_META = 'openid-connect-generic-last-token-response';

function danotech_id_token_roles( $user_id ) {
	$response = get_user_meta( $user_id, DANOTECH_TOKEN_META, true );
	if ( is_string( $response ) ) {
		$response = json_decode( $response, true );
	}
	if ( empty( $response['id_token'] ) ) {
		return null; // Not an Entra ID sign-in (e.g. the local break-glass admin).
	}
	$parts = explode( '.', $response['id_token'] );
	if ( count( $parts ) < 2 ) {
		return null;
	}
	$payload = json_decode( base64_decode( strtr( $parts[1], '-_', '+/' ) ), true );
	return isset( $payload['roles'] ) && is_array( $payload['roles'] ) ? $payload['roles'] : array();
}

function danotech_apply_entra_role( $user_login, $user ) {
	$roles = danotech_id_token_roles( $user->ID );
	if ( null === $roles ) {
		return;
	}
	$target = 'subscriber';
	foreach ( DANOTECH_ROLE_MAP as $app_role => $wp_role ) { // ordered highest first
		if ( in_array( $app_role, $roles, true ) ) {
			$target = $wp_role;
			break;
		}
	}
	$current = (array) $user->roles;
	if ( $current !== array( $target ) ) {
		$user->set_role( $target );
		error_log( sprintf( '[danotech-entra-roles] %s: %s -> %s (token roles: %s)',
			$user_login, implode( ',', $current ), $target, implode( ',', $roles ) ) );
	}
}
// Priority 20: after the OIDC plugin has stored the token response.
add_action( 'wp_login', 'danotech_apply_entra_role', 20, 2 );
