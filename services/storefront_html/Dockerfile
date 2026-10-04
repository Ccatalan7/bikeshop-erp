# The HTML storefront as a native binary on an empty image.
#
# deploy_cloud_run.sh builds it from a staged context that holds only this
# service and the shared core, with the repository's layout:
#   packages/vinabike_public_core/
#   services/storefront_html/
# The Dart version matches the repository's FVM SDK (.fvm/flutter_sdk).
FROM dart:3.10.4 AS build

WORKDIR /src
COPY packages/vinabike_public_core packages/vinabike_public_core
COPY services/storefront_html services/storefront_html

WORKDIR /src/services/storefront_html
RUN dart pub get --enforce-lockfile
RUN dart compile exe bin/server.dart -o /out/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server

EXPOSE 8080
CMD ["/app/server"]
