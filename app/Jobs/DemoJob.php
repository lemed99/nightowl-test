<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

final class DemoJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public readonly string $mode = 'ok') {}

    public function handle(): void
    {
        Log::info('DemoJob running', ['mode' => $this->mode]);
        DB::table('users')->count();
        usleep(random_int(50_000, 250_000));

        if ($this->mode === 'fail') {
            throw new \RuntimeException('DemoJob intentional failure');
        }
    }
}
