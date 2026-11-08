package api;

import static config.BaseHelpers.*;
import static config.SessionKeys.*;
import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

import java.util.List;
import java.util.Map;

import io.gatling.javaapi.core.ChainBuilder;

public class Navigation {

    /**
     * Navigate to the homepage and extract navigation links.
     * Should extract links for Tables, Chairs, Cart, and Checkout.
     *
     */
    public static ChainBuilder navigateToHomePage(String group) {
        return group(group).on(
                exec(
                        http("GET /")
                                .get("/")
                                .check(regex("Performance testing Essentials").exists())
                                .check(regex("href=\"(?:https?://[^/]+)?/(tables)\"").find().saveAs(TABLES))
                                .check(regex("href=\"(?:https?://[^/]+)?/(chairs)\"").find().saveAs(CHAIRS))
                                .check(regex("href=\"(?:https?://[^/]+)?/(cart)\"").find().saveAs(CART))
                                .check(regex("href=\"(?:https?://[^/]+)?/(checkout)\"").find().saveAs(CHECKOUT))
                )
        );
    }

    /**
     * Navigate to a category page (Tables or Chairs) and extract a random product
     * link.
     */
    public static ChainBuilder navigateToCategory(String group, String sessionKey) {
        return group(group).on(
                exec(
                        http("GET " + expression(sessionKey))
                                .get("/" + expression(sessionKey))
                                .check(
                                        regex(BASE_URL + "/products/(.+?)\"")
                                                .findRandom()
                                                .saveAs(randomProductKey(sessionKey))
                                )
                )
        );
    }

    /**
     * Navigate to a product page and extract productId and cart_content.
     */
    public static ChainBuilder navigateToProduct(String group, String sessionKey) {
        final String rndVar = randomProductKey(sessionKey);

        return group(group).on(
                exec(
                        http("GET /products/#{" + rndVar + "}")
                                .get("/products/#{" + rndVar + "}")
                                .check(regex("<link rel='shortlink' href='" + BASE_URL + "/\\?p=(\\d+)' />")
                                        .saveAs("productId"))
                                .check(regex("<input hidden type=\"hidden\" name=\"cart_content\" value='(.*?)'>")
                                        .optional()
                                        .saveAs("cart_content"))
                )
        );
    }

    /**
     * Add a product to cart via POST request to admin-ajax.php.
     */
    public static ChainBuilder addProductToCart(String prefix, int quantity) {
        return group(prefix + "addToCart").on(
                exec(
                        http("POST " + ADMIN_AJAX)
                                .post(ADMIN_AJAX)
                                .formParamMap(Map.of(
                                        "action", "ic_add_to_cart",
                                        "add_cart_data",
                                        "current_product=#{productId}&cart_content=#{cart_content}&current_quantity=" + quantity,
                                        "cart_widget", CART_WIDGET_DISABLED,
                                        "cart_container", CART_CONTAINER_DISABLED
                                ))
                                .check(regex("Added!").exists())
                )
        );
    }

    /**
     * Navigate to the cart page and update cart_content.
     */
    public static ChainBuilder navigateToCart(String group, String sessionKey) {
        return group(group).on(
                exec(
                        http("GET " + expression(sessionKey))
                                .get("/" + expression(sessionKey))
                                .check(regex("Cart").exists())
                                .check(regex("name=\"cart_content\" value='(.*?)'")
                                        .optional()
                                        .saveAs("cart_content"))
                )
        );
    }

    /**
     * Navigate to the checkout page and extract order details:
     * products, trans_id, total_net, and build products_price.
     * The country is NOT taken from the page: like in JMeter it comes from the CSV feeder (cart_country).
     */
    public static ChainBuilder navigateToCheckout(String group, String sessionKey) {
        return group(group).on(
                exec(
                        http("GET " + expression(sessionKey))
                                .get("/" + expression(sessionKey))

                                .check(
                                        regex("name=\"cart_content\" value='(.*?)'")
                                                .optional()
                                                .saveAs("cart_content")
                                )

                                .check(
                                        regex("name=\"(product_price_\\d+__)\" value=\"([^\"]+)\"")
                                                .captureGroups(2)
                                                .findAll()
                                                .saveAs("products_price_list")
                                )

                                .check(
                                        regex("value=\"(\\d+)\" name=\"trans_id\"")
                                                .saveAs("trans_id")
                                )

                                .check(
                                        regex("name=\"total_net\" value=\"(.+?)\"")
                                                .saveAs("total_net")
                                )
                ),

                exec(session -> {
                    List<?> prices = session.getList("products_price_list");

                    String productsPrice;

                    if (prices.isEmpty()) {
                        productsPrice = "0";
                    } else {
                        productsPrice = prices.stream()
                                .map(price -> {
                                    if (price instanceof List<?> groups) {
                                        return groups.get(0) + "=" + groups.get(1);
                                    }

                                    return price.toString();
                                })
                                .reduce((left, right) -> left + "&" + right)
                                .orElse("0");
                    }

                    return session
                            .set("products_price", productsPrice)
                            .set("order_redirect", BASE_URL + "/thank-you");
                })
        );
    }

    /**
     * Choose a country (cart_country from the CSV feeder, as in JMeter) and optionally extract state_code.
     */
    public static ChainBuilder chooseCountry(String group) {
        return group(group).on(
                exec(
                        http("POST " + ADMIN_AJAX)
                                .post(ADMIN_AJAX)
                                .formParamMap(Map.of(
                                        "action", "ic_state_dropdown",
                                        "country_code", "#{cart_country}",
                                        "state_code", ""
                                ))
                                .check(regex("\"value\":\"([A-Z0-9_]+)\"")
                                        .findRandom()
                                        .optional()
                                        .saveAs("state_code"))
                ),
                exec(session -> {
                    if (!session.contains("state_code")) {
                        return session.set("state_code", "");
                    }
                    return session;
                })
        );
    }

    /**
     * Submit the order using multipart form data from bodies/submit.txt template.
     */
    public static ChainBuilder placeOrder(String group, String sessionKey) {
        return group(group).on(
                exec(
                        http("POST " + expression(sessionKey))
                                .post("/" + expression(sessionKey))
                                .asFormUrlEncoded()
                                .body(ElFileBody("bodies/submit.txt"))
                                .check(regex("Thank You").exists())
                )
        );
    }

    private static String expression(String sessionKey) {
        return "#{" + sessionKey + "}";
    }

    private static String randomProductKey(String sessionKey) {
        return "rnd" + sessionKey;
    }
}
