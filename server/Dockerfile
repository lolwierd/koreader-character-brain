FROM node:22-alpine

WORKDIR /app
COPY package.json ./
COPY src ./src
RUN chmod -R a+rX /app

ENV NODE_ENV=production
EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:8787/health').then(r=>{process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"

USER node
CMD ["node", "src/index.js"]
