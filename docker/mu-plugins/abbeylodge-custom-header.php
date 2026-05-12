<?php
/**
 * Plugin Name: Abbey Lodge Custom Header
 * Description: Replaces the Hello Elementor default header with branded hotel header.
 */

// Disable Hello Elementor's built-in header.
add_filter('hello_elementor_header_footer', '__return_false');

// Inject custom header HTML right after <body>.
add_action('wp_body_open', function () {
    $home_url = esc_url(home_url('/'));
    $phone    = '+44 1234 567890';
    $phone_href = 'tel:+441234567890';
    $address  = '123 High Street, London, W1A 1AB';
    ?>
    <header class="abbeylodge-header" role="banner">
        <div class="abbeylodge-header__inner">
            <div class="abbeylodge-header__brand">
                <h1 class="abbeylodge-header__title">
                    <a href="<?php echo $home_url; ?>">Abbey Lodge Hotel</a>
                </h1>
            </div>
            <div class="abbeylodge-header__contact">
                <span class="abbeylodge-header__phone">
                    <a href="<?php echo esc_url($phone_href); ?>"><?php echo esc_html($phone); ?></a>
                </span>
                <span class="abbeylodge-header__address"><?php echo esc_html($address); ?></span>
            </div>
        </div>
    </header>
    <?php
});
