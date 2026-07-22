import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { SystemUsageView } from "./components";
import { refreshSystemUsage } from "./store";

export const systemUsageWidget: RefreshableBabyMenuWidget = {
  id: "system-usage",
  title: "MACBOOK · LOAD",
  viewRefreshIntervalMs: 2000,
  refreshView: refreshSystemUsage,
  render: () => <SystemUsageView />,
};
