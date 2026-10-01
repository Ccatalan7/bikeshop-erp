#!/usr/bin/env bash
# C1 nativo del TaskFormDialog, aceptado el 2026-09-30
# (.tmp/e2e/android-task-form-20260930-055146.log). El lanzador común de los
# recorridos nativos es run_android_local_journey.sh; este nombre se conserva.
#
#   scripts/e2e/run_task_form_android_local.sh [--build-only] [--reuse-apk] [--start-services]
exec "$(dirname "${BASH_SOURCE[0]}")/run_android_local_journey.sh" --journey task-form "$@"
