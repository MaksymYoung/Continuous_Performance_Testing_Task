package config;

import io.gatling.javaapi.http.HttpProtocolBuilder;

import static io.gatling.javaapi.http.HttpDsl.http;

public class BaseHelpers {

    private BaseHelpers() {
    }

    /**
     * Public URL of the site as the application itself knows it (WordPress "siteurl", e.g. http://localhost).
     * Used in regex checks (links in the HTML contain this URL) and in the order redirect.
     */
    public static final String BASE_URL = System.getProperty("BASE_URL", "http://localhost");

    /**
     * Address Gatling really connects to (default: same as BASE_URL).
     * In Jenkins (Docker) it is the Docker host gateway, e.g. http://172.17.0.1.
     */
    public static final String TARGET_URL = System.getProperty("TARGET_URL", BASE_URL);

    /**
     * Value of the Host header (default: empty = not set). WordPress redirects to its siteurl unless the
     * Host header is "localhost", so Jenkins passes -DHOST_HEADER=localhost (same as the JMeter test).
     */
    public static final String HOST_HEADER = System.getProperty("HOST_HEADER", "");

    private static HttpProtocolBuilder buildProtocol() {
        HttpProtocolBuilder protocol = http
                .baseUrl(TARGET_URL)
                .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .acceptEncodingHeader("gzip, deflate")
                .acceptLanguageHeader("en-US,en;q=0.5")
                .upgradeInsecureRequestsHeader("1")
                .userAgentHeader(
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                );
        return HOST_HEADER.isBlank() ? protocol : protocol.header("Host", HOST_HEADER);
    }

    /** HTTP protocol configuration with realistic browser headers. */
    public static final HttpProtocolBuilder HTTP_PROTOCOL = buildProtocol();

    /**
     * Admin AJAX endpoint (e.g., "/wp-admin/admin-ajax.php").
     */
    public static final String ADMIN_AJAX = "/wp-admin/admin-ajax.php";
    public static final String CART_WIDGET_DISABLED = "0";
    public static final String CART_CONTAINER_DISABLED = "0";

    /**
     * Percentage of users adding chairs (default: 50).
     */
    public static final double CHAIRS_PERCENTAGE = Double.parseDouble(
            System.getProperty("CHAIRS_PERCENTAGE", "50"));

    /**
     * Percentage of users proceeding to cart (default: 30).
     */
    public static final double CART_PERCENTAGE = Double.parseDouble(
            System.getProperty("CART_PERCENTAGE", "30"));

    /** Think time center in milliseconds (default: 3500). */
    public static final int THINK_TIME_CENTER = Integer.parseInt(
            System.getProperty("think_time_center", "3500"));

    /** Think time deviation in milliseconds (default: 1500). */
    public static final int THINK_TIME_DEVIATION = Integer.parseInt(
            System.getProperty("think_time_deviation", "1500"));

    /**
     * Standard deviation for Gaussian think-time pauses as a percentage of THINK_TIME (default: 20).
     */
    public static final double THINK_TIME_STD_DEV_PERCENT = Double.parseDouble(
            System.getProperty("THINK_TIME_STD_DEV_PERCENT", "20"));

    /**
     * Number of virtual users (Open model) - reads from -Dramp_threads or -DOPEN_USERS.
     */
    public static final int OPEN_USERS = Integer.parseInt(
            System.getProperty("OPEN_USERS", System.getProperty("ramp_threads", "200")));

    /**
     * Number of concurrent users (Closed model).
     */
    public static final int CONCURRENT_USERS =
            Integer.parseInt(System.getProperty("CONCURRENT_USERS", System.getProperty("ramp_threads", "200")));

    /**
     * Ramp-up period in seconds - reads from -Dramp_sec (default: 2100 / 35 minutes).
     */
    public static final int RAMP_UP_PERIOD = Integer.parseInt(
            System.getProperty("RAMP_UP_PERIOD", System.getProperty("ramp_sec", "2100")));

    /**
     * Test hold period in seconds after ramp-up (default: 3600 / 1 hour).
     */
    public static final int TEST_HOLD_SEC = Integer.parseInt(
            System.getProperty("TEST_HOLD_SEC", System.getProperty("test_hold_sec", "3600")));

    // ---- Response time test (closed model, steady-state load, PerfTestSimulation) ----

    /** Initial number of concurrent users at the start of the ramp-up (default: 1). */
    public static final int CLOSED_START_USERS = Integer.parseInt(
            System.getProperty("CLOSED_START_USERS", "1"));

    /**
     * Target (steady) number of concurrent users (default: 128 = 80% of the 160 VU saturation point).
     */
    public static final int CLOSED_USERS = Integer.parseInt(
            System.getProperty("CLOSED_USERS", "128"));

    /**
     * Ramp-up to the target load in seconds - reads -DRAMP_UP_PERIOD or -Dramp_sec (default: 300).
     * Separate from RAMP_UP_PERIOD, whose default is 2100.
     */
    public static final int STEADY_RAMP_SEC = Integer.parseInt(
            System.getProperty("RAMP_UP_PERIOD", System.getProperty("ramp_sec", "300")));

    /**
     * Steady-state hold in seconds - reads -DTEST_HOLD_SEC or -Dtest_hold_sec (default: 1800 / 30 minutes).
     * Separate from TEST_HOLD_SEC, whose default is 3600.
     */
    public static final int STEADY_HOLD_SEC = Integer.parseInt(
            System.getProperty("TEST_HOLD_SEC", System.getProperty("test_hold_sec", "1800")));

    /** Total duration of the load profile in seconds (ramp-up + hold). */
    public static final long TEST_DURATION_SEC = (long) STEADY_RAMP_SEC + STEADY_HOLD_SEC;

    /**
     * Assertion set for the response time test - reads -DASSERTION_TYPE or -Dassertion_type
     * (default: responseTime). Separate from ASSERTION_TYPE, whose default is smokeTest.
     */
    public static final String STEADY_ASSERTION_TYPE = System.getProperty(
            "ASSERTION_TYPE", System.getProperty("assertion_type", "responseTime"));

    /**
     * Programmatic step timeout in ms (default: 10000; 0 = disabled). A step slower than this is
     * counted as an error even if Gatling did not abort the request.
     */
    public static final long STEP_TIMEOUT_MS = Long.getLong("STEP_TIMEOUT_MS", 10_000L);

    /** Extra time in seconds for active sessions to finish after the profile ends (default: 300). */
    public static final int SHUTDOWN_GRACE_SEC = 300;

    /** Interval in seconds between progress lines printed to the console (default: 60). */
    public static final int PROGRESS_LOG_INTERVAL_SEC = 60;

    /**
     * Load model: open or closed (default: open).
     */
    public static final String LOAD_MODEL = System.getProperty("LOAD_MODEL", "open");

    /**
     * Tables quantity in units (default: 1).
     */
    public static final int TABLES_QUANTITY = Integer.parseInt(
            System.getProperty("TABLES_QUANTITY", "1"));

    /**
     * Chairs quantity in units (default: 1).
     */
    public static final int CHAIRS_QUANTITY = Integer.parseInt(
            System.getProperty("CHAIRS_QUANTITY", "1"));

    /**
     * Minimum percentage of successful requests (default: 99.0).
     */
    public static final double SUCCESSFUL_REQUESTS_PERCENT = Double.parseDouble(
            System.getProperty("SUCCESSFUL_REQUESTS_PERCENT", "90.0"));

    /** Home page 95th percentile response time threshold in milliseconds (default: 3000). */
    public static final int HOME_PAGE_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("HOME_PAGE_P95_RESPONSE_TIME_MS", "3000"));

    /** Category page 95th percentile response time threshold in milliseconds (default: 2500). */
    public static final int CATEGORY_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CATEGORY_P95_RESPONSE_TIME_MS", "2500"));

    /** Tables page 95th percentile response time threshold in milliseconds (default: 3000). */
    public static final int TABLES_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("TABLES_P95_RESPONSE_TIME_MS", "3000"));

    /** Tables add-to-cart 95th percentile response time threshold in milliseconds (default: 4000). */
    public static final int TABLES_ADD_TO_CART_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("TABLES_ADD_TO_CART_P95_RESPONSE_TIME_MS", "4000"));

    /** Chairs page 95th percentile response time threshold in milliseconds (default: 3000). */
    public static final int CHAIRS_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CHAIRS_P95_RESPONSE_TIME_MS", "3000"));

    /** Chairs add-to-cart 95th percentile response time threshold in milliseconds (default: 4000). */
    public static final int CHAIRS_ADD_TO_CART_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CHAIRS_ADD_TO_CART_P95_RESPONSE_TIME_MS", "4000"));

    /** Cart page 95th percentile response time threshold in milliseconds (default: 3000). */
    public static final int CART_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CART_P95_RESPONSE_TIME_MS", "3000"));

    /** Checkout page 95th percentile response time threshold in milliseconds (default: 4000). */
    public static final int CHECKOUT_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CHECKOUT_P95_RESPONSE_TIME_MS", "4000"));

    /** Choosing country 95th percentile response time threshold in milliseconds (default: 2000). */
    public static final int CHOOSING_COUNTRY_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("CHOOSING_COUNTRY_P95_RESPONSE_TIME_MS", "2000"));

    /** Place order 95th percentile response time threshold in milliseconds (default: 4000). */
    public static final int PLACE_ORDER_P95_RESPONSE_TIME_MS = Integer.parseInt(
            System.getProperty("PLACE_ORDER_P95_RESPONSE_TIME_MS", "4000"));

    public static final String ASSERTION_TYPE = System.getProperty(
            "ASSERTION_TYPE", "smokeTest"
    );
}
