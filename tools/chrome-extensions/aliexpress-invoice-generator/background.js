(function () {
  'use strict';

  const SIDE_PANEL_PATH = 'sidepanel.html';

  async function enableSidePanelAction() {
    if (!chrome.sidePanel) return;
    try {
      if (chrome.sidePanel.setPanelBehavior) {
        await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
      }
      if (chrome.sidePanel.setOptions) {
        await chrome.sidePanel.setOptions({ path: SIDE_PANEL_PATH, enabled: true });
      }
    } catch (error) {
      console.warn('AliExpress invoice side panel setup failed:', error);
    }
  }

  chrome.runtime.onInstalled.addListener(() => {
    enableSidePanelAction();
  });

  chrome.runtime.onStartup.addListener(() => {
    enableSidePanelAction();
  });

  chrome.action.onClicked.addListener(async (tab) => {
    try {
      await enableSidePanelAction();
      if (chrome.sidePanel && chrome.sidePanel.open) {
        await chrome.sidePanel.open({ windowId: tab.windowId });
      }
    } catch (error) {
      console.warn('AliExpress invoice side panel open failed:', error);
    }
  });

  enableSidePanelAction();
}());
