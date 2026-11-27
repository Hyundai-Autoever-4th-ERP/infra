package erp.gateway;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DomainRouteTest {
    private static final List<HttpServer> upstreams = new ArrayList<>();

    @DynamicPropertySource
    static void configureServices(DynamicPropertyRegistry properties) throws IOException {
        for (String domain : List.of("auth", "item", "inventory", "procurement", "sales", "notification")) {
            HttpServer upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            upstream.createContext("/", exchange -> {
                byte[] body = (domain + " " + exchange.getRequestURI()).getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, body.length);
                try (var output = exchange.getResponseBody()) {
                    output.write(body);
                }
            });
            upstream.start();
            upstreams.add(upstream);
            properties.add(domain.toUpperCase(java.util.Locale.ROOT) + "_SERVICE_URL",
                    () -> "http://127.0.0.1:" + upstream.getAddress().getPort());
        }
    }

    @AfterAll
    static void stopServices() {
        upstreams.forEach(upstream -> upstream.stop(0));
    }

    @ParameterizedTest
    @CsvSource({
        "auth,/api/auth/login", "auth,/api/users/me/password",
        "item,/api/v1/items/42", "item,/api/v1/locations/1",
        "inventory,/api/inventory/stocks?page=1",
        "procurement,/api/v1/vendors", "procurement,/api/v1/purchase-orders",
        "sales,/api/v1/sales-orders", "notification,/api/v1/notifications",
        "auth,/health/auth", "item,/health/item", "inventory,/health/inventory",
        "procurement,/health/procurement", "sales,/health/sales", "notification,/health/notification"
    })
    void forwardsToExpectedService(String domain, String path, @LocalServerPort int port) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path)).GET().build();
        var response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString());
        assertEquals(200, response.statusCode());
        assertEquals(domain + " " + (path.startsWith("/health/") ? "/actuator/health" : path), response.body());
    }
}
