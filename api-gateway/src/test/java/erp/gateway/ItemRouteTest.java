package erp.gateway;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ItemRouteTest {
    private static HttpServer upstream;

    @DynamicPropertySource
    static void configureItemService(DynamicPropertyRegistry properties) throws IOException {
        upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        upstream.createContext("/", exchange -> {
            byte[] path = exchange.getRequestURI().toString().getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, path.length);
            try (var body = exchange.getResponseBody()) {
                body.write(path);
            }
        });
        upstream.start();
        properties.add("ITEM_SERVICE_URL", () -> "http://127.0.0.1:" + upstream.getAddress().getPort());
    }

    @AfterAll
    static void stopItemService() {
        if (upstream != null) {
            upstream.stop(0);
        }
    }

    @ParameterizedTest
    @ValueSource(strings = {"/api/v1/items/42", "/api/v1/locations/1"})
    void forwardsPathToItemService(String path, @LocalServerPort int port) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path)).build();
        var response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString());

        assertEquals(200, response.statusCode());
        assertEquals(path, response.body());
    }
}
