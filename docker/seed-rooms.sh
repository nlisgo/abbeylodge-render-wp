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
