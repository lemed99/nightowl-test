<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Schedule::command('nightowl-test:demo')->everyMinute()->name('nightowl-demo-heartbeat');

// Tier-1 demo retention: keep raw telemetry to a few hours so the demo DB and
// the non-rollup pages (logs/mail/notifications/commands/scheduled-tasks/raw
// exceptions) stay lively without unbounded growth. Rollups are kept far longer
// (their own retention) so the trend charts still span the default ranges. Only
// schedule this when this install is acting as the demo feeder.
if (config('nightowl.simulator.enabled', false)) {
    Schedule::command('nightowl:prune --hours=6')
        ->everyThirtyMinutes()
        ->withoutOverlapping();
}
