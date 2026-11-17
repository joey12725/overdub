/**
 * The one place the concrete modules are wired together (ARCHITECTURE "Modules"): the Three.js
 * renderer, the Harmonograph audio engine and the DOM UI are created here and handed to the App
 * shell (src/game/shell.ts), which only ever sees their src/contracts.ts facades.
 */
import { createAudio } from '../audio/index';
import { createRenderer } from '../render/index';
import { createUi } from '../ui/index';
import { buildApp, type App } from './shell';

export { App } from './shell';

/** Dev-build handle for automated smoke tests (window.__overdub). Absent from production builds. */
export interface OverdubDevHandle {
  app: App;
  readonly screen: string;
  readonly phase: string | null;
  view(): ReturnType<NonNullable<App['session']>['view']> | null;
  session(): App['session'];
}

export function createApp(mount: HTMLElement): App {
  const app = buildApp(mount, { createRenderer, createAudio, createUi });
  if (import.meta.env?.DEV) {
    const handle: OverdubDevHandle = {
      app,
      get screen() {
        return app.screen;
      },
      get phase() {
        return app.session?.phase ?? null;
      },
      view: () => app.session?.view() ?? null,
      session: () => app.session,
    };
    (globalThis as { __overdub?: OverdubDevHandle }).__overdub = handle;
  }
  return app;
}
