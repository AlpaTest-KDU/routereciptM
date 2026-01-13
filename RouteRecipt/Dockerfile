FROM eclipse-temurin:17-jre
WORKDIR /app

COPY RouteRecipt-0.0.1-SNAPSHOT.jar app.jar
COPY application.yml application.yml

EXPOSE 8090

ENTRYPOINT ["java","-jar","app.jar","--spring.config.location=/app/application.yml"]
