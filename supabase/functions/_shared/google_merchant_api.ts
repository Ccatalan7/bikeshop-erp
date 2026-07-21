const merchantApiOrigin = "https://merchantapi.googleapis.com";

export function merchantProductUrl(args: {
  accountId: string;
  contentLanguage: string;
  feedLabel: string;
  offerId: string;
}) {
  const productId = [
    args.contentLanguage,
    args.feedLabel,
    args.offerId,
  ].join("~");
  const encodedProductId = base64Url(
    new TextEncoder().encode(productId),
  );
  return `${merchantApiOrigin}/products/v1/accounts/${
    encodeURIComponent(args.accountId)
  }/products/${encodedProductId}`;
}

export function merchantDataSourcesUrl(accountId: string) {
  return `${merchantApiOrigin}/datasources/v1/accounts/${
    encodeURIComponent(accountId)
  }/dataSources`;
}

export function merchantDataSourceFetchUrl(name: string) {
  return `${merchantApiOrigin}/datasources/v1/${name}:fetch`;
}

export function isFetchableMerchantDataSource(value: unknown) {
  if (!isRecord(value) || !isRecord(value.fileInput)) return false;
  return isRecord(value.fileInput.fetchSettings);
}

export function merchantProductSummary(
  payload: unknown,
  country = "CL",
) {
  const product = isRecord(payload) ? payload : {};
  const productStatus = isRecord(product.productStatus) ? product.productStatus : {};
  const destinationStatuses = Array.isArray(productStatus.destinationStatuses)
    ? productStatus.destinationStatuses.filter(isRecord)
    : [];
  const itemLevelIssues = Array.isArray(productStatus.itemLevelIssues)
    ? productStatus.itemLevelIssues.filter(isRecord)
    : [];
  const attributes = isRecord(product.productAttributes)
    ? product.productAttributes
    : isRecord(product.attributes)
    ? product.attributes
    : {};

  return {
    status: merchantDestinationStatus(destinationStatuses, country),
    productId: text(product.name) || null,
    title: text(attributes.title) || null,
    link: text(attributes.link) || null,
    destinationStatuses,
    itemLevelIssues,
    issueCount: itemLevelIssues.length,
  };
}

export function merchantDestinationStatus(
  destinationStatuses: Array<Record<string, unknown>>,
  country = "CL",
) {
  if (
    destinationStatuses.some((status) => countryList(status.disapprovedCountries).includes(country))
  ) return "disapproved";
  if (
    destinationStatuses.some((status) => countryList(status.pendingCountries).includes(country))
  ) return "pending";
  if (
    destinationStatuses.some((status) => countryList(status.approvedCountries).includes(country))
  ) return "approved";
  return "found";
}

function countryList(value: unknown) {
  return Array.isArray(value) ? value.map(text).filter(Boolean) : [];
}

function text(value: unknown) {
  return String(value ?? "").trim();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
