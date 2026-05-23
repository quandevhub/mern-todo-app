FROM node:22-alpine AS base
WORKDIR /app
COPY package.json .

FROM base AS development
RUN npm install
COPY . .
CMD ["node", "--watch", "server.js"]

FROM base AS production
RUN npm install --omit=dev
COPY . .
CMD ["node", "server.js"]
