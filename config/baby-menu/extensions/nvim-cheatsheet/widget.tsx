import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { NvimCheatsheetView } from "./components";

export const nvimCheatsheetWidget: RefreshableBabyMenuWidget = {
  id: "nvim-cheatsheet",
  title: "NVIM · CHEATSHEET",
  render: () => <NvimCheatsheetView />,
};
