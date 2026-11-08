package scenarios;

import static config.BaseHelpers.*;
import static config.SessionKeys.*;
import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

import api.Navigation;
import io.gatling.javaapi.core.ChainBuilder;
import io.gatling.javaapi.core.FeederBuilder;
import io.gatling.javaapi.core.Session;

import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;

public class UserFlow {

    /**
     * Session key: a failure has already occurred in this iteration, so the remaining steps are skipped.
     */
    public static final String ITERATION_FAILED = "iterationFailed";

    /**
     * Customer data for checkout (cart_name, cart_address, cart_postal, cart_city, cart_country,
     * cart_phone, cart_email).
     */
    private static final FeederBuilder<String> CHECKOUT_FEEDER = csv("data/checkout.csv").circular();

    /**
     * Returns a chain of steps (ChainBuilder) rather than a scenario, so that it can be
     * embedded into another scenario via exec(...).
     *
     * Failures are handled in page(): each step records its own result (including an error),
     * after which the remaining steps of the iteration are skipped.
     */
    public static ChainBuilder userJourney(double chairs, double cart) {
        return exec(flushHttpCache())
                .exec(flushCookieJar())
                .feed(CHECKOUT_FEEDER)
                .exec(
                        page("001_HomePage", Navigation.navigateToHomePage("001_HomePage")),
                        page("002_Category", Navigation.navigateToCategory("002_Category", TABLES)),
                        page("003_Tables", Navigation.navigateToProduct("003_Tables", TABLES)),
                        page("004_Tables_", Navigation.addProductToCart("004_Tables_", TABLES_QUANTITY)),
                        randomSwitch().on(
                                percent(chairs).then(
                                        exec(
                                                page("005_Category", Navigation.navigateToCategory("005_Category", CHAIRS)),
                                                page("006_Chairs", Navigation.navigateToProduct("006_Chairs", CHAIRS)),
                                                page("007_Chairs_", Navigation.addProductToCart("007_Chairs_", CHAIRS_QUANTITY))
                                        )
                                )
                        ),
                        randomSwitch().on(
                                percent(cart).then(
                                        exec(
                                                page("008_Cart", Navigation.navigateToCart("008_Cart", CART)),
                                                page("009_Checkout", Navigation.navigateToCheckout("009_Checkout", CHECKOUT)),
                                                page("010_Choosing_Country", Navigation.chooseCountry("010_Choosing_Country")),
                                                page("011_Place_Order", Navigation.placeOrder("011_Place_Order", CHECKOUT))
                                        )
                                )
                        )
                );
    }

    /**
     * A step (group of requests): measures the actual elapsed time, marks the step as failed
     * if it exceeds STEP_TIMEOUT_MS, then applies think time.
     */
    private static ChainBuilder page(String requestName, ChainBuilder actionChain) {
        String startKey = "t0_" + requestName;
        return doIf(session -> !session.contains(ITERATION_FAILED)).then(
                exec(session -> session.set(startKey, System.currentTimeMillis()))
                        .exitBlockOnFail().on(actionChain)
                        .exec(session -> {
                            long elapsed = System.currentTimeMillis() - session.getLong(startKey);
                            boolean timedOut = STEP_TIMEOUT_MS > 0 && elapsed > STEP_TIMEOUT_MS;
                            boolean failed = session.isFailed() || timedOut;
                            return failed ? session.markAsSucceeded().set(ITERATION_FAILED, true) : session;
                        })
                        .doIf(session -> !session.contains(ITERATION_FAILED)).then(
                                pause(UserFlow::gaussianThinkTime)
                        )
        );
    }

    /**
     * Think time with a normal distribution, like the Gaussian Random Timer in JMeter:
     * mean THINK_TIME_CENTER, standard deviation THINK_TIME_DEVIATION, minimum 0.
     */
    private static Duration gaussianThinkTime(Session session) {
        double value = THINK_TIME_CENTER + ThreadLocalRandom.current().nextGaussian() * THINK_TIME_DEVIATION;
        return Duration.ofMillis(Math.max(0L, Math.round(value)));
    }
}
