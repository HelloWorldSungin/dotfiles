import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { AntigravityQuotaView } from "./components";
import { refreshAntigravityQuota } from "./store";

export const antigravityQuotaWidget: RefreshableBabyMenuWidget = {
  id: "antigravity-quota",
  title: "GEMINI · ANTIGRAVITY",
  viewRefreshIntervalMs: 5 * 60 * 1000,
  refreshView: refreshAntigravityQuota,
  render: () => <AntigravityQuotaView />,
};
