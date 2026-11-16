# ---------------------------------------------------------------
# Nordwind AD Lab — imagen de la web estática
# Base: nginx sin privilegios (corre como usuario 'nginx', puerto 8080)
# ---------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Nuestra config sustituye a la default
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Solo copiamos lo que la web necesita (nada de scripts .ps1 ni docs)
COPY --chown=nginx:nginx index.html ataque.html fundamentos.html /usr/share/nginx/html/
COPY --chown=nginx:nginx assets/   /usr/share/nginx/html/assets/
COPY --chown=nginx:nginx diagrams/ /usr/share/nginx/html/diagrams/

EXPOSE 8080

# Docker comprueba solo si nginx sigue respondiendo
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1
