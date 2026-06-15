FROM node:22-alpine

WORKDIR /app
COPY package.json ./
COPY src ./src
RUN chmod -R a+rX /app

ENV NODE_ENV=production
EXPOSE 8787

USER node
CMD ["node", "src/index.js"]
