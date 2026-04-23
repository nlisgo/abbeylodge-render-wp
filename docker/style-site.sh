#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Abbey Lodge — Site branding and custom CSS
#
# Sets site title, tagline, and injects custom CSS via the WordPress
# Customizer "Additional CSS" mechanism (custom_css post type).
#
# Idempotent: safe to run on every boot.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { printf '[style-site] %s\n' "$*"; }

WP="wp --allow-root --path=/var/www/html"

# ---- Site identity ---------------------------------------------------------
${WP} option update blogname "Abbey Lodge Hotel"
${WP} option update blogdescription "Comfortable rooms in the heart of the city"
log "Site identity updated."

# ---- Theme mod: show tagline in header ------------------------------------
ACTIVE_THEME=$(${WP} theme list --status=active --field=name 2>/dev/null || true)
if [ -n "${ACTIVE_THEME}" ]; then
    ${WP} theme mod set hello_header_tagline "yes" 2>/dev/null || true
    log "Header tagline enabled for ${ACTIVE_THEME}."
fi

# ---- Custom CSS ------------------------------------------------------------
read -r -d '' CUSTOM_CSS << 'CSSEOF' || true
/* ==========================================================================
   Abbey Lodge Hotel — Custom Styles
   Injected via WordPress Customizer Additional CSS (custom_css post type)
   ========================================================================== */

/* --- Font stack --------------------------------------------------------- */
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
    color: #334155;
}

/* --- Header ------------------------------------------------------------- */
header.site-header,
.site-header {
    background-color: #1e293b !important;
    border-bottom: 3px solid #b45309;
}

.site-header .site-title,
.site-header .site-title a {
    color: #ffffff !important;
    text-decoration: none;
}

.site-header .site-description,
.site-header .site-tagline {
    color: #94a3b8 !important;
}

.site-header a {
    color: #e2e8f0 !important;
}

.site-header a:hover {
    color: #b45309 !important;
}

/* --- Footer ------------------------------------------------------------- */
footer.site-footer,
.site-footer {
    background-color: #1e293b !important;
    color: #94a3b8;
    border-top: 3px solid #b45309;
}

.site-footer a {
    color: #e2e8f0 !important;
}

.site-footer a:hover {
    color: #b45309 !important;
}

/* --- Buttons & links ---------------------------------------------------- */
a {
    color: #b45309;
}

a:hover {
    color: #92400e;
}

.wp-block-button__link,
button[type="submit"],
input[type="submit"],
.button,
.mphb-book-button,
.mphb-confirm-reservation {
    background-color: #b45309 !important;
    color: #ffffff !important;
    border: none !important;
    border-radius: 6px !important;
    padding: 12px 28px !important;
    font-weight: 600 !important;
    text-transform: uppercase !important;
    letter-spacing: 0.5px !important;
    cursor: pointer;
    transition: background-color 0.2s ease;
}

.wp-block-button__link:hover,
button[type="submit"]:hover,
input[type="submit"]:hover,
.button:hover,
.mphb-book-button:hover,
.mphb-confirm-reservation:hover {
    background-color: #92400e !important;
    color: #ffffff !important;
}

/* --- Booking search form ------------------------------------------------ */
.mphb-availability-search-form label,
.mphb_sc_search-form label {
    text-transform: uppercase;
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.5px;
    color: #475569;
}

.mphb-availability-search-form input,
.mphb-availability-search-form select,
.mphb_sc_search-form input,
.mphb_sc_search-form select {
    border: 1px solid #cbd5e1;
    border-radius: 6px;
    padding: 10px 14px;
    font-size: 15px;
    transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.mphb-availability-search-form input:focus,
.mphb-availability-search-form select:focus,
.mphb_sc_search-form input:focus,
.mphb_sc_search-form select:focus {
    border-color: #b45309;
    box-shadow: 0 0 0 3px rgba(180, 83, 9, 0.15);
    outline: none;
}

/* --- Room listing cards ------------------------------------------------- */
.mphb_sc_rooms-wrapper .mphb-room-type,
.mphb-room-type-listing {
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 24px;
    margin-bottom: 24px;
    transition: box-shadow 0.2s ease;
    background: #ffffff;
}

.mphb_sc_rooms-wrapper .mphb-room-type:hover,
.mphb-room-type-listing:hover {
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
}

.mphb-room-type-title,
.mphb-room-type-title a {
    color: #1e293b !important;
    font-weight: 700;
}

.mphb-regular-price {
    color: #b45309;
    font-size: 20px;
    font-weight: 700;
}

/* --- Cover block (hero) ------------------------------------------------- */
.wp-block-cover {
    margin-bottom: 0 !important;
}

/* --- Responsive --------------------------------------------------------- */
@media (max-width: 768px) {
    .wp-block-cover .wp-block-heading {
        font-size: 32px !important;
    }

    .wp-block-columns {
        gap: 16px !important;
    }

    .mphb-availability-search-form .mphb-reserve-room-section,
    .mphb_sc_search-form .mphb-reserve-room-section {
        flex-direction: column;
    }
}
CSSEOF

# Upsert the custom_css post for the active theme
if [ -n "${ACTIVE_THEME}" ]; then
    EXISTING_CSS_ID=$(${WP} post list \
        --post_type=custom_css \
        --post_status=publish \
        --name="${ACTIVE_THEME}" \
        --field=ID \
        --format=csv 2>/dev/null | head -1 || true)

    if [ -n "${EXISTING_CSS_ID}" ] && [ "${EXISTING_CSS_ID}" != "ID" ]; then
        ${WP} post update "${EXISTING_CSS_ID}" --post_content="${CUSTOM_CSS}" >/dev/null
        log "Custom CSS updated (post #${EXISTING_CSS_ID})."
    else
        CSS_POST_ID=$(${WP} post create \
            --post_type=custom_css \
            --post_status=publish \
            --post_name="${ACTIVE_THEME}" \
            --post_title="Custom CSS" \
            --post_content="${CUSTOM_CSS}" \
            --porcelain)
        log "Custom CSS created (post #${CSS_POST_ID})."
    fi

    # Point the theme mod at the custom_css post
    ${WP} eval "set_theme_mod('custom_css_post_id', (int) get_page_by_path('${ACTIVE_THEME}', OBJECT, 'custom_css')->ID);" 2>/dev/null || true
else
    log "WARN: No active theme detected — skipping custom CSS."
fi

log "Site styling complete."
