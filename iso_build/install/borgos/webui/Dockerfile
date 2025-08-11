FROM nginx:alpine

# Copy static files
COPY index.html /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf

# Create non-root user
RUN adduser -D -H -u 1000 -s /sbin/nologin borgos && \
    chown -R borgos:borgos /usr/share/nginx/html && \
    chown -R borgos:borgos /var/cache/nginx && \
    chown -R borgos:borgos /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown borgos:borgos /var/run/nginx.pid

USER borgos

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]