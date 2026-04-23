#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Abbey Lodge — Seed MotoPress Hotel Booking data
#
# Creates room types, individual rooms, a default season, nightly rates,
# and MPHB booking-flow pages (Search Results, Checkout, Booking Confirmed)
# so that a fresh deploy produces a working hotel booking site with no
# manual admin clicking required.
#
# Idempotent: exits immediately when mphb_room_type posts already exist.
# Controlled by: ABBEYLODGE_SEED_ROOMS env var (default: skip).
# ---------------------------------------------------------------------------
set -euo pipefail

log() { printf '[seed-rooms] %s\n' "$*"; }

WP="wp --allow-root --path=/var/www/html"

# ---- Guard 1: env var opt-in ------------------------------------------------
SEED="${ABBEYLODGE_SEED_ROOMS:-0}"
case "${SEED}" in
    0|no|false|NO|FALSE)
        log "ABBEYLODGE_SEED_ROOMS is '${SEED}' — skipping room seed."
        exit 0
        ;;
esac

# ---- Guard 2: already seeded? -----------------------------------------------
EXISTING=$(${WP} post list --post_type=mphb_room_type --post_status=any --format=count 2>/dev/null || echo 0)
if [[ "${EXISTING}" -gt 0 ]]; then
    log "${EXISTING} room type(s) already exist — skipping seed."
    exit 0
fi

log "Seeding MotoPress Hotel Booking data..."

# ---- Season ------------------------------------------------------------------
log "Creating default season (2026-01-01 → 2099-12-31)..."
SEASON_ID=$(${WP} post create \
    --post_type=mphb_season \
    --post_title="Default" \
    --post_status=publish \
    --porcelain)

${WP} post meta update "${SEASON_ID}" mphb_start_date "2026-01-01"
${WP} post meta update "${SEASON_ID}" mphb_end_date   "2099-12-31"

# mphb_days is a serialized array of integers 0–6 (Sun=0 … Sat=6)
${WP} eval "update_post_meta(${SEASON_ID}, 'mphb_days', array(0,1,2,3,4,5,6));"

log "  Season #${SEASON_ID} created."

# ---- Room types, rooms, and rates -------------------------------------------
#
# Inventory table:
#   Type              Adults  Children  Bed     Count  Price(£/night)
#   Single            1       0         Single  4      79
#   Double            2       0         Double  15     89
#   Twin              2       0         Twin    6      89
#   Superior Double   2       0         Double  10     99
#
create_room_type() {
    local title="$1" adults="$2" children="$3" bed="$4" count="$5" price="$6"

    log "Creating room type: ${title} (×${count}, £${price}/night)..."

    # -- Room type post
    local type_id
    type_id=$(${WP} post create \
        --post_type=mphb_room_type \
        --post_title="${title}" \
        --post_status=publish \
        --porcelain)

    ${WP} post meta update "${type_id}" mphb_adults_capacity       "${adults}"
    ${WP} post meta update "${type_id}" mphb_children_capacity     "${children}"
    ${WP} post meta update "${type_id}" mphb_base_adults_capacity  "${adults}"
    ${WP} post meta update "${type_id}" mphb_base_children_capacity "${children}"
    ${WP} post meta update "${type_id}" mphb_bed                   "${bed}"

    log "  Room type #${type_id} created."

    # -- Individual rooms
    for i in $(seq 1 "${count}"); do
        local room_id
        room_id=$(${WP} post create \
            --post_type=mphb_room \
            --post_title="${title} ${i}" \
            --post_status=publish \
            --porcelain)
        ${WP} post meta update "${room_id}" mphb_room_type_id "${type_id}"
    done
    log "  ${count} room(s) created."

    # -- Rate with season price
    local rate_id
    rate_id=$(${WP} post create \
        --post_type=mphb_rate \
        --post_title="${title} — Standard Rate" \
        --post_status=publish \
        --porcelain)

    ${WP} post meta update "${rate_id}" mphb_room_type_id "${type_id}"

    # mphb_season_prices is a nested PHP array:
    #   array( array( 'season' => <id>, 'price' => array( 'periods' => array(...), 'prices' => array(...) ) ) )
    ${WP} eval "
        update_post_meta(${rate_id}, 'mphb_season_prices', array(
            array(
                'season'  => ${SEASON_ID},
                'price'   => array(
                    'periods' => array(1),
                    'prices'  => array(${price}.00),
                ),
            ),
        ));
    "

    log "  Rate #${rate_id} created."
}

create_room_type "Single"           1 0 "Single" 4  79
create_room_type "Double"           2 0 "Double" 15 89
create_room_type "Twin"             2 0 "Twin"   6  89
create_room_type "Superior Double"  2 0 "Double" 10 99

# ---- Currency ----------------------------------------------------------------
${WP} eval "update_option('mphb_currency_symbol', 'GBP');"
log "Currency set to GBP."

# ---- MPHB booking-flow pages ------------------------------------------------
# These pages use shortcodes rendered by the MotoPress plugin.
log "Creating booking-flow pages..."

create_page() {
    local title="$1" slug="$2" content="${3:-}"

    local page_id
    page_id=$(${WP} post create \
        --post_type=page \
        --post_title="${title}" \
        --post_name="${slug}" \
        --post_status=publish \
        --post_content="${content}" \
        --porcelain)

    log "  Page '${title}' (#${page_id}) created." >&2
    echo "${page_id}"
}

# Rooms listing page
create_page "Rooms" "rooms" '[mphb_rooms]'

# Booking-flow pages
SEARCH_RESULTS_ID=$(create_page \
    "Search Results" "search-results" \
    '[mphb_search_results]')
CHECKOUT_ID=$(create_page \
    "Checkout" "checkout" \
    '[mphb_checkout]')
CONFIRMATION_ID=$(create_page \
    "Booking Confirmed" "booking-confirmed" \
    '[mphb_booking_confirmation]')

# ---- Homepage with hero, search form, and about section --------------------
read -r -d '' HOME_CONTENT << 'GUTENBERG' || true
<!-- wp:cover {"overlayColor":"#1e293b","customOverlayColor":"#1e293b","minHeight":420,"isDark":true,"style":{"spacing":{"padding":{"top":"80px","bottom":"80px"}}}} -->
<div class="wp-block-cover is-dark" style="padding-top:80px;padding-bottom:80px;min-height:420px"><span aria-hidden="true" class="wp-block-cover__background has-background-dim-100 has-background-dim" style="background-color:#1e293b"></span><div class="wp-block-cover__inner-container"><!-- wp:heading {"textAlign":"center","level":1,"style":{"typography":{"fontSize":"48px","fontWeight":"700"},"color":{"text":"#ffffff"}}} -->
<h1 class="wp-block-heading has-text-align-center has-text-color" style="color:#ffffff;font-size:48px;font-weight:700">Abbey Lodge Hotel</h1>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","style":{"typography":{"fontSize":"20px"},"color":{"text":"#cbd5e1"}}} -->
<p class="has-text-align-center has-text-color" style="color:#cbd5e1;font-size:20px">Comfortable rooms in the heart of the city</p>
<!-- /wp:paragraph --></div></div>
<!-- /wp:cover -->

<!-- wp:group {"style":{"spacing":{"padding":{"top":"60px","bottom":"60px","left":"20px","right":"20px"}}},"layout":{"type":"constrained","contentSize":"720px"}} -->
<div class="wp-block-group" style="padding-top:60px;padding-bottom:60px;padding-left:20px;padding-right:20px"><!-- wp:heading {"textAlign":"center","level":2,"style":{"typography":{"fontSize":"32px","fontWeight":"600"},"color":{"text":"#1e293b"}}} -->
<h2 class="wp-block-heading has-text-align-center has-text-color" style="color:#1e293b;font-size:32px;font-weight:600">Check Availability</h2>
<!-- /wp:heading -->

<!-- wp:shortcode -->
[mphb_availability_search]
<!-- /wp:shortcode --></div>
<!-- /wp:group -->

<!-- wp:group {"style":{"color":{"background":"#f8fafc"},"spacing":{"padding":{"top":"60px","bottom":"60px","left":"20px","right":"20px"}}},"layout":{"type":"constrained","contentSize":"960px"}} -->
<div class="wp-block-group has-background" style="background-color:#f8fafc;padding-top:60px;padding-bottom:60px;padding-left:20px;padding-right:20px"><!-- wp:heading {"textAlign":"center","level":2,"style":{"typography":{"fontSize":"32px","fontWeight":"600"},"color":{"text":"#1e293b"}}} -->
<h2 class="wp-block-heading has-text-align-center has-text-color" style="color:#1e293b;font-size:32px;font-weight:600">Welcome to Abbey Lodge</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","style":{"typography":{"fontSize":"18px"},"color":{"text":"#475569"}}} -->
<p class="has-text-align-center has-text-color" style="color:#475569;font-size:18px">Situated in the heart of the city, Abbey Lodge Hotel offers comfortable accommodation at affordable prices. Whether you are visiting for business or leisure, our friendly team is here to make your stay memorable.</p>
<!-- /wp:paragraph -->

<!-- wp:columns {"style":{"spacing":{"blockGap":{"left":"30px"},"margin":{"top":"40px"}}}} -->
<div class="wp-block-columns" style="margin-top:40px"><!-- wp:column {"style":{"border":{"radius":"8px"},"spacing":{"padding":{"top":"30px","bottom":"30px","left":"20px","right":"20px"}},"color":{"background":"#ffffff"}}} -->
<div class="wp-block-column has-background" style="border-radius:8px;background-color:#ffffff;padding-top:30px;padding-bottom:30px;padding-left:20px;padding-right:20px"><!-- wp:heading {"textAlign":"center","level":3,"style":{"typography":{"fontSize":"36px","fontWeight":"700"},"color":{"text":"#b45309"}}} -->
<h3 class="wp-block-heading has-text-align-center has-text-color" style="color:#b45309;font-size:36px;font-weight:700">35</h3>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","style":{"typography":{"fontSize":"16px","fontWeight":"600"},"color":{"text":"#334155"}}} -->
<p class="has-text-align-center has-text-color" style="color:#334155;font-size:16px;font-weight:600">Rooms</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column -->

<!-- wp:column {"style":{"border":{"radius":"8px"},"spacing":{"padding":{"top":"30px","bottom":"30px","left":"20px","right":"20px"}},"color":{"background":"#ffffff"}}} -->
<div class="wp-block-column has-background" style="border-radius:8px;background-color:#ffffff;padding-top:30px;padding-bottom:30px;padding-left:20px;padding-right:20px"><!-- wp:heading {"textAlign":"center","level":3,"style":{"typography":{"fontSize":"36px","fontWeight":"700"},"color":{"text":"#b45309"}}} -->
<h3 class="wp-block-heading has-text-align-center has-text-color" style="color:#b45309;font-size:36px;font-weight:700">Central</h3>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","style":{"typography":{"fontSize":"16px","fontWeight":"600"},"color":{"text":"#334155"}}} -->
<p class="has-text-align-center has-text-color" style="color:#334155;font-size:16px;font-weight:600">Location</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column -->

<!-- wp:column {"style":{"border":{"radius":"8px"},"spacing":{"padding":{"top":"30px","bottom":"30px","left":"20px","right":"20px"}},"color":{"background":"#ffffff"}}} -->
<div class="wp-block-column has-background" style="border-radius:8px;background-color:#ffffff;padding-top:30px;padding-bottom:30px;padding-left:20px;padding-right:20px"><!-- wp:heading {"textAlign":"center","level":3,"style":{"typography":{"fontSize":"36px","fontWeight":"700"},"color":{"text":"#b45309"}}} -->
<h3 class="wp-block-heading has-text-align-center has-text-color" style="color:#b45309;font-size:36px;font-weight:700">£79</h3>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","style":{"typography":{"fontSize":"16px","fontWeight":"600"},"color":{"text":"#334155"}}} -->
<p class="has-text-align-center has-text-color" style="color:#334155;font-size:16px;font-weight:600">Per Night</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns --></div>
<!-- /wp:group -->
GUTENBERG

HOME_ID=$(create_page "Home" "home" "${HOME_CONTENT}")

${WP} option update show_on_front page
${WP} option update page_on_front "${HOME_ID}"
log "Static homepage set with hero, search form, and about section."

# ---- MPHB page settings -----------------------------------------------------
# Tell MotoPress which pages serve each role in the booking flow.
${WP} eval "
    update_option('mphb_search_results_page', ${SEARCH_RESULTS_ID});
    update_option('mphb_checkout_page',       ${CHECKOUT_ID});
    update_option('mphb_booking_confirmed_page', ${CONFIRMATION_ID});
"
log "MPHB page settings configured."

# ---- Summary -----------------------------------------------------------------
TYPES=$(${WP} post list --post_type=mphb_room_type --post_status=publish --format=count)
ROOMS=$(${WP} post list --post_type=mphb_room --post_status=publish --format=count)
SEASONS=$(${WP} post list --post_type=mphb_season --post_status=publish --format=count)
RATES=$(${WP} post list --post_type=mphb_rate --post_status=publish --format=count)
PAGES=$(${WP} post list --post_type=page --post_status=publish --format=count)

log "Done! ${TYPES} room type(s), ${ROOMS} room(s), ${SEASONS} season(s), ${RATES} rate(s), ${PAGES} page(s)."
