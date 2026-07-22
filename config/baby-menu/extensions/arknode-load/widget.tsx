import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { ArknodeLoadView } from "./components";
import { refreshArknodeLoad } from "./store";

export const arknodeLoadWidget: RefreshableBabyMenuWidget = {
  id: "arknode-load",
  title: "ARKNODE-AI · LOAD",
  viewRefreshIntervalMs: 3000,
  refreshView: refreshArknodeLoad,
  render: () => <ArknodeLoadView />,
};
