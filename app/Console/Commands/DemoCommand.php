<?php

namespace App\Console\Commands;

use App\Jobs\DemoJob;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

class DemoCommand extends Command
{
    protected $signature = 'nightowl-test:demo {--fail : dispatch a failing job}';

    protected $description = 'Emits every telemetry type against the local agent';

    public function handle(): int
    {
        $this->info('Running NightOwl demo command…');

        User::query()->limit(5)->get();
        Cache::put('demo:cmd', now()->toIso8601String(), 60);
        Log::info('demo command heartbeat');
        DemoJob::dispatch($this->option('fail') ? 'fail' : 'ok');

        $this->info('Done.');

        return self::SUCCESS;
    }
}
