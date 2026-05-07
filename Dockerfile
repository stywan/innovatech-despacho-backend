# =============================================================================
# EP2 - Innovatech Chile | Backend (Spring Boot + Java 17 + MySQL)
# Multi-stage build: maven:17-alpine (build) → eclipse-temurin:17-jre (run)
# Usuario no root para mínimo privilegio
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

LABEL maintainer="Innovatech Chile DevOps Team"
LABEL stage="builder"

WORKDIR /app

# Copiar Maven Wrapper y pom.xml primero → cacheo de dependencias Maven
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B --no-transfer-progress

# Copiar código fuente
COPY src ./src

# Compilar y empaquetar usando Maven Wrapper (sin tests en CI para velocidad)
RUN ./mvnw clean package -DskipTests -B --no-transfer-progress

# ── Stage 2: Run ──────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS production

LABEL maintainer="Innovatech Chile DevOps Team"
LABEL stage="production"

# Instalar curl para health check
RUN apk add --no-cache curl

# Crear grupo y usuario no root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copiar únicamente el JAR generado en stage builder
COPY --from=builder /app/target/*.jar app.jar

# Asignar propiedad del archivo al usuario no root
RUN chown appuser:appgroup app.jar

# Cambiar a usuario sin privilegios de root
USER appuser

# Puerto de la API (server.port=8081 en application.properties)
EXPOSE 8081

# Health check: verifica que la API de despachos responde
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
  CMD curl -f http://localhost:8081/api/v1/despachos || exit 1

# Entrada: ejecutar el JAR
# -Djava.security.egd mejora la velocidad de arranque en contenedores
ENTRYPOINT ["java", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-jar", "app.jar"]
