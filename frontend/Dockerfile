FROM node:22-alpine AS development
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
ENV CHOKIDAR_USEPOLLING=true
ENV WATCHPACK_POLLING=true
CMD ["npm", "start"]

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* ./
RUN npm install
COPY . .
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

FROM nginx:alpine AS production
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
