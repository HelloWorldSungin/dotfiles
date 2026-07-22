import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { OpenCodeGoQuotaView } from "./components";
import { refreshGoQuota } from "./store";

export const openCodeGoQuotaWidget: RefreshableBabyMenuWidget = {
  id: "opencode-go-quota",
  title: "OPENCODE GO · QUOTA",
  viewRefreshIntervalMs: 5 * 60 * 1000,
  refreshView: refreshGoQuota,
  render: () => <OpenCodeGoQuotaView />,
};
