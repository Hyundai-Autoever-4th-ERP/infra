FROM eclipse-temurin:25-jdk AS build
WORKDIR /app
COPY gradle gradle
COPY gradlew settings.gradle ./
COPY api-gateway api-gateway
RUN ./gradlew --no-daemon :api-gateway:check :api-gateway:bootJar

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build /app/api-gateway/build/libs/gateway.jar app.jar
USER 10001
ENTRYPOINT ["java", "-jar", "app.jar"]
