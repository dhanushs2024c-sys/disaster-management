
FROM nginx:alpine

ARG RELEASE_MODE=STABLE

COPY index.html /usr/share/nginx/html/index.html
COPY health.html /usr/share/nginx/html/health.html

# The FAULTY mode deliberately removes the health endpoint.
# Kubernetes must detect that the new release is not ready.
RUN if [ "$RELEASE_MODE" = "FAULTY" ]; then \
      rm -f /usr/share/nginx/html/health.html; \
    fi

EXPOSE 80
