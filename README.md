# Innovatech Chile – Backend (Spring Boot + PostgreSQL)

API backend contenedorizada de Innovatech Chile. Desplegada en una instancia EC2 en **subred privada** de AWS. Solo accesible desde la EC2 del frontend (controlado por Security Groups).

---

## Tecnologías

| Componente | Versión |
|---|---|
| Java | 21 (JRE Alpine) |
| Spring Boot | 3+ |
| Maven (build) | 3.9 Alpine |
| PostgreSQL | 16 Alpine |

---

## Estructura relevante

```
backend/
├── Dockerfile                    # Multi-stage: build (maven) + run (jre)
├── docker-compose.yml            # Stack completo: backend + PostgreSQL
├── .env.example                  # Variables de entorno requeridas
└── .github/
    └── workflows/
        └── deploy.yml            # Pipeline CI/CD GitHub Actions
```

---

## Ejecutar localmente con Docker

### 1. Clonar y configurar variables

```bash
git clone https://github.com/TU_USUARIO/backend.git
cd backend
cp .env.example .env
# Editar .env: al menos definir DB_PASSWORD
```

### 2. Levantar el stack completo (backend + PostgreSQL)

```bash
# Construir y levantar todos los servicios
docker compose up -d --build

# Verificar contenedores
docker ps

# Ver logs del backend
docker compose logs -f backend

# Ver logs de la base de datos
docker compose logs -f db
```

### 3. Verificar que la API responde

```bash
curl http://localhost:8080/actuator/health
# Esperado: {"status":"UP"}
```

### 4. Detener sin borrar datos

```bash
docker compose down
# El volumen postgres_data se conserva
```

### 5. Detener y borrar todo (incluyendo datos)

```bash
docker compose down -v
```

---

## Persistencia de datos

Se utiliza un **named volume** llamado `innovatech_postgres_data` para los datos de PostgreSQL.

### ¿Por qué named volume en lugar de bind mount?

| Criterio | Named Volume | Bind Mount |
|---|---|---|
| Portabilidad | ✅ Gestionado por Docker | ❌ Depende de rutas del host |
| Seguridad | ✅ No expone directorios del host | ⚠️ Expone sistema de archivos |
| Facilidad | ✅ Docker gestiona la ubicación | ❌ Requiere crear directorios |
| Backup | ✅ `docker volume` comandos | Manual |

Los datos sobreviven: `docker compose down` y `docker compose up` sin perder información.

---

## Pipeline CI/CD (GitHub Actions)

El pipeline se activa al hacer **push a la rama `deploy`**.

### Flujo

```
push a rama deploy
       │
       ▼
┌─────────────────────────────┐
│  Job 1: build-and-push      │
│  • Checkout código          │
│  • Docker Buildx            │
│  • Login Docker Hub         │
│  • mvn package (en imagen)  │
│  • docker push (sha+latest) │
└────────────┬────────────────┘
             │ éxito
             ▼
┌──────────────────────────────────┐
│  Job 2: deploy                   │
│  • SSH a EC2 backend             │
│    VÍA EC2 frontend (bastion)    │
│  • docker pull                   │
│  • Verificar PostgreSQL running  │
│  • docker stop/rm backend        │
│  • docker run nuevo backend      │
│  • docker image prune            │
└──────────────────────────────────┘
```

> **Nota sobre el bastion**: la EC2 del backend está en subred privada (sin IP pública). El workflow usa la EC2 del frontend como jump host (`proxy_host`) para llegar a ella por SSH.

### GitHub Secrets requeridos

Configurar en: `Settings → Secrets and variables → Actions`

| Secret | Descripción |
|---|---|
| `DOCKERHUB_USERNAME` | Usuario de Docker Hub |
| `DOCKERHUB_TOKEN` | Access token de Docker Hub |
| `EC2_FRONTEND_HOST` | IP pública EC2 frontend (actúa como bastion) |
| `EC2_BACKEND_HOST` | IP privada EC2 backend |
| `EC2_USER` | Usuario SSH (ej: `ec2-user` o `ubuntu`) |
| `EC2_SSH_KEY` | Contenido de la clave privada `.pem` |
| `DB_NAME` | Nombre de la base de datos |
| `DB_USER` | Usuario de PostgreSQL |
| `DB_PASSWORD` | Contraseña de PostgreSQL |

### Activar despliegue

```bash
git checkout deploy
git push origin deploy
```

---

## Despliegue manual en EC2 backend

```bash
# En la EC2 backend (acceder vía bastion frontend)
docker network create backend-net 2>/dev/null || true

# Levantar PostgreSQL si no está corriendo
docker run -d \
  --name innovatech-db \
  --restart unless-stopped \
  --network backend-net \
  -v innovatech_postgres_data:/var/lib/postgresql/data \
  -e POSTGRES_DB=innovatech \
  -e POSTGRES_USER=innovauser \
  -e POSTGRES_PASSWORD=<password> \
  postgres:16-alpine

# Levantar backend
docker pull TUUSUARIO/innovatech-backend:latest
docker run -d \
  --name innovatech-backend \
  --restart unless-stopped \
  --network backend-net \
  -p 8080:8080 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://innovatech-db:5432/innovatech \
  -e SPRING_DATASOURCE_USERNAME=innovauser \
  -e SPRING_DATASOURCE_PASSWORD=<password> \
  -e SPRING_PROFILES_ACTIVE=prod \
  TUUSUARIO/innovatech-backend:latest
```

---

## Arquitectura AWS

```
Internet
    │
    ▼ (solo puerto 80)
[EC2 Frontend – Subred Pública]
    │
    │ Puerto 8080 (regla SG interna)
    ▼
[EC2 Backend – Subred Privada] ←── Sin acceso desde internet
    │
    │ Red Docker interna (backend-net)
    ▼
[Contenedor PostgreSQL]
    │
    └── Named Volume: innovatech_postgres_data
```

---

## Buenas prácticas aplicadas (DevOps)

- **Multi-stage build**: imagen final ~200MB (solo JRE + JAR, sin Maven ni fuentes)
- **Usuario no root**: el proceso Java corre como `appuser`
- **Dependency caching**: `pom.xml` se copia antes que `src/` para cachear `mvn dependency:go-offline`
- **Health check**: Spring Boot Actuator en `/actuator/health`
- **`depends_on` con `condition: service_healthy`**: el backend espera a que PostgreSQL esté listo
- **Named volume justificado**: datos de BD persisten entre reinicios de contenedor
- **Secrets en GitHub Actions**: credenciales de BD y AWS nunca en el código
- **Bastion host**: acceso SSH a subred privada respetando arquitectura de seguridad
