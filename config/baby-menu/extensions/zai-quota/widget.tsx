import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { ZaiQuotaView } from "./components";
import { refreshZaiQuota } from "./store";

export const zaiQuotaWidget: RefreshableBabyMenuWidget = {
  id: "zai-quota",
  title: "Z.AI · QUOTA",
  viewRefreshIntervalMs: 5 * 60 * 1_000,
  refreshView: refreshZaiQuota,
  render: () => <ZaiQuotaView />,
};
