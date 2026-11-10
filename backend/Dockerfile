FROM node:22-alpine

WORKDIR /app

COPY package.json ./
COPY src ./src

RUN mkdir -p data

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8787

EXPOSE 8787

CMD ["node", "src/server.mjs"]
