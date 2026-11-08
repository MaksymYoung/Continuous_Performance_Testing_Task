package assertions;

import io.gatling.javaapi.core.Assertion;

import static config.BaseHelpers.*;
import static io.gatling.javaapi.core.CoreDsl.*;

import java.util.List;
import java.util.stream.Stream;

/**
 * Contains performance assertion sets for validating application performance.
 */
public class PerformanceAssertions {

    /**
     * Constant for smoke test assertion type.
     */
    public static final String SMOKE_TEST = "smokeTest";

    /**
     * Constant for e-commerce order assertion type.
     */
    public static final String ECOMMERCE_ORDER = "ecommerceOrder";

    /**
     * Constant for the steady-state response time test assertion type.
     */
    public static final String RESPONSE_TIME = "responseTime";

    /**
     * Basic smoke test assertions for minimal validation.
     * Should check: ≥99% successful requests.
     */
    public static final List<Assertion> smokeTestAssertions = List.of(
            global().successfulRequests().percent().gte(SUCCESSFUL_REQUESTS_PERCENT)
    );

    /**
     * Full e-commerce order flow assertions with 95th percentile response times.
     * Should check response times for each request group:
     * - 001_HomePage
     * - 002_Category
     * - 003_Tables
     * - 004_Tables_addToCart
     * - 005_Category
     * - 006_Chairs
     * - 007_Chairs_addToCart
     * - 008_Cart
     * - 009_Checkout
     * - 010_Choosing_Country
     * - 011_Place_Order
     */
    public static final List<Assertion> ecommerceOrderAssertions = List.of(
            details("001_HomePage").responseTime().percentile3().lte(HOME_PAGE_P95_RESPONSE_TIME_MS),
            details("002_Category").responseTime().percentile3().lte(CATEGORY_P95_RESPONSE_TIME_MS),
            details("003_Tables").responseTime().percentile3().lte(TABLES_P95_RESPONSE_TIME_MS),
            details("004_Tables_addToCart").responseTime().percentile3().lte(TABLES_ADD_TO_CART_P95_RESPONSE_TIME_MS),
            details("005_Category").responseTime().percentile3().lte(CATEGORY_P95_RESPONSE_TIME_MS),
            details("006_Chairs").responseTime().percentile3().lte(CHAIRS_P95_RESPONSE_TIME_MS),
            details("007_Chairs_addToCart").responseTime().percentile3().lte(CHAIRS_ADD_TO_CART_P95_RESPONSE_TIME_MS),
            details("008_Cart").responseTime().percentile3().lte(CART_P95_RESPONSE_TIME_MS),
            details("009_Checkout").responseTime().percentile3().lte(CHECKOUT_P95_RESPONSE_TIME_MS),
            details("010_Choosing_Country").responseTime().percentile3().lte(CHOOSING_COUNTRY_P95_RESPONSE_TIME_MS),
            details("011_Place_Order").responseTime().percentile3().lte(PLACE_ORDER_P95_RESPONSE_TIME_MS)
    );

    /**
     * Response time test at stable load: P95 per request group (as in ecommerceOrder)
     * plus the minimum share of successful requests (SUCCESSFUL_REQUESTS_PERCENT, passed as 99 by the run script).
     */
    public static final List<Assertion> responseTimeAssertions = Stream.concat(
            ecommerceOrderAssertions.stream(),
            Stream.of(global().successfulRequests().percent().gte(SUCCESSFUL_REQUESTS_PERCENT))
    ).toList();

}
