# ---------------------------------------------------------------
# Nordwind AD Lab — imagen de la web estática (plantilla A)
# nginx oficial SIN root (uid 101), rama ESTABLE con soporte.
# 1.30 = estable desde abril 2026. Cada abril sale estable nueva → revisar.
# ---------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.30-alpine

# Mi config sustituye a la de por defecto
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Borrar la página de bienvenida y 50x.html de la imagen: la imagen ya corre
# como nginx y no puede borrar archivos de root → root solo para este paso
WORKDIR /usr/share/nginx/html
USER root
RUN rm -rf ./*
USER nginx

# Copiar SOLO lo necesario. Sin --chown: queda de root → nginx lo lee, no lo modifica
COPY index.html ataque.html fundamentos.html ./
COPY assets   ./assets
COPY diagrams ./diagrams

# Sin CMD (la imagen ya arranca nginx en primer plano) y sin HEALTHCHECK (va en el compose)
