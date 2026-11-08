package assertions;

import io.gatling.javaapi.core.Assertion;

import static assertions.PerformanceAssertions.*;

import java.util.List;
import java.util.Map;

/**
 * Maps assertion types to their corresponding assertion lists.
 */
public class AssertionsMap {

    /**
     * Map linking assertion types to assertion lists:
     * - SMOKE_TEST → smokeTestAssertions
     * - ECOMMERCE_ORDER → ecommerceOrderAssertions
     * - RESPONSE_TIME → responseTimeAssertions
     */
    public static final Map<String, List<Assertion>> ASSERT_MAPPING = Map.of(
            SMOKE_TEST, smokeTestAssertions,
            ECOMMERCE_ORDER, ecommerceOrderAssertions,
            RESPONSE_TIME, responseTimeAssertions
    );
}
