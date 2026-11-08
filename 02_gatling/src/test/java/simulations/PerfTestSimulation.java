package simulations;

import static assertions.AssertionsMap.ASSERT_MAPPING;
import static config.BaseHelpers.*;
import static io.gatling.javaapi.core.CoreDsl.*;

import io.gatling.javaapi.core.Assertion;
import io.gatling.javaapi.core.ClosedInjectionStep;
import io.gatling.javaapi.core.PopulationBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;
import scenarios.UserFlow;

import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Backend response time test under STEADY load, CLOSED model.
 *
 * Profile: ramp-up from CLOSED_START_USERS to CLOSED_USERS over RAMP_UP_PERIOD seconds, then hold
 * exactly CLOSED_USERS concurrent users for TEST_HOLD_SEC seconds.
 * For this test: saturation point 160 VU, target load 80% = 128 VU, hold 30 min (1800 s).
 * As soon as a user finishes the scenario, Gatling starts a new one, so the system always has
 * exactly N users.
 *
 * The measured window (steady state) is the TEST_HOLD_SEC after the ramp-up ends. The start and end
 * of the window are printed to the console ("STEADY STATE" lines); use them to see which part of the run is the steady state.
 *
 * Parameters: -DCLOSED_USERS, -DCLOSED_START_USERS, -DRAMP_UP_PERIOD, -DTEST_HOLD_SEC,
 * -DASSERTION_TYPE (default responseTime).
 */
public class PerfTestSimulation extends Simulation {

    /** Number of users currently running the scenario (a sanity check: should match the profile). */
    private static final AtomicInteger ACTIVE_USERS = new AtomicInteger();

    /** Test start time (ms), set in before(). */
    private static volatile long startMillis = 0;

    private static final ScheduledExecutorService metricsScheduler =
            Executors.newSingleThreadScheduledExecutor(r -> {
                Thread t = new Thread(r, "gatling-metrics-reporter");
                t.setDaemon(true);
                return t;
            });

    {
        startActiveUsersReporter();

        setUp(populations())
                .protocols(HTTP_PROTOCOL)
                .maxDuration(Duration.ofSeconds(TEST_DURATION_SEC + SHUTDOWN_GRACE_SEC))
                .assertions(assertions());
    }

    @Override
    public void before() {
        startMillis = System.currentTimeMillis();
        long steadyFrom = startMillis + STEADY_RAMP_SEC * 1000L;
        long steadyTo = steadyFrom + STEADY_HOLD_SEC * 1000L;
        System.out.printf("STEADY STATE plan: ramp %d -> %d users in %d s, then hold %d users for %d s%n",
                CLOSED_START_USERS, CLOSED_USERS, STEADY_RAMP_SEC, CLOSED_USERS, STEADY_HOLD_SEC);
        System.out.printf("STEADY STATE window: %s - %s (local time)%n", clock(steadyFrom), clock(steadyTo));
    }

    private static String clock(long millis) {
        return DateTimeFormatter.ofPattern("HH:mm:ss")
                .withZone(ZoneId.systemDefault())
                .format(Instant.ofEpochMilli(millis));
    }

    @Override
    public void after() {
        metricsScheduler.shutdownNow();
    }

    private void startActiveUsersReporter() {
        final AtomicBoolean steadyLogged = new AtomicBoolean();
        final AtomicLong tick = new AtomicLong();
        metricsScheduler.scheduleAtFixedRate(() -> {
            try {
                int active = activeUsers();

                if (startMillis == 0) {
                    return;
                }
                long elapsedMs = System.currentTimeMillis() - startMillis;
                if (elapsedMs >= STEADY_RAMP_SEC * 1000L && steadyLogged.compareAndSet(false, true)) {
                    System.out.printf("STEADY STATE started at %s, active users: %d (target %d)%n",
                            clock(System.currentTimeMillis()), active, CLOSED_USERS);
                }
                if (tick.incrementAndGet() % PROGRESS_LOG_INTERVAL_SEC == 0) {
                    System.out.printf("[%s] elapsed %d s, active users: %d (target %d)%n",
                            clock(System.currentTimeMillis()), elapsedMs / 1000, active, CLOSED_USERS);
                }
            } catch (Exception ignored) {
            }
        }, 0, 1, TimeUnit.SECONDS);
    }

    /**
     * Actual number of active users (a counter of sessions in progress), printed to the console.
     * Returns 0 before the test starts.
     */
    private static int activeUsers() {
        if (startMillis == 0) {
            return 0;
        }
        return Math.max(0, ACTIVE_USERS.get());
    }

    /**
     * User scenario with an active-users counter.
     */
    private static ScenarioBuilder journey() {
        return scenario("E-commerce End-to-End Journey")
                .exec(session -> {
                    ACTIVE_USERS.incrementAndGet();
                    return session;
                })
                .exec(UserFlow.userJourney(CHAIRS_PERCENTAGE, CART_PERCENTAGE))
                .exec(session -> {
                    ACTIVE_USERS.decrementAndGet();
                    return session;
                });
    }

    private PopulationBuilder injection() {
        if (CLOSED_USERS <= 0 || STEADY_HOLD_SEC <= 0 || STEADY_RAMP_SEC <= 0) {
            throw new IllegalArgumentException("CLOSED_USERS, RAMP_UP_PERIOD and TEST_HOLD_SEC must be > 0");
        }
        if (CLOSED_START_USERS > CLOSED_USERS) {
            throw new IllegalArgumentException("CLOSED_START_USERS (" + CLOSED_START_USERS
                    + ") must not exceed CLOSED_USERS (" + CLOSED_USERS + ")");
        }

        List<ClosedInjectionStep> steps = new ArrayList<>();

        steps.add(rampConcurrentUsers(CLOSED_START_USERS).to(CLOSED_USERS).during(Duration.ofSeconds(STEADY_RAMP_SEC)));

        steps.add(constantConcurrentUsers(CLOSED_USERS).during(Duration.ofSeconds(STEADY_HOLD_SEC)));
        return journey().injectClosed(steps);
    }

    private PopulationBuilder[] populations() {
        return new PopulationBuilder[]{injection()};
    }

    private Assertion[] assertions() {
        List<Assertion> selectedAssertions = ASSERT_MAPPING.get(STEADY_ASSERTION_TYPE);
        if (selectedAssertions == null) {
            throw new IllegalArgumentException(
                    "Unsupported ASSERTION_TYPE '" + STEADY_ASSERTION_TYPE + "'. Supported values: " + ASSERT_MAPPING.keySet()
            );
        }
        return selectedAssertions.toArray(new Assertion[0]);
    }
}
