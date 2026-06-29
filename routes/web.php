<?php

use App\Jobs\DemoJob;
use App\Mail\DemoMail;
use App\Models\User;
use App\Notifications\DemoNotification;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Route;

Route::get('/', fn () => view('welcome'));

Route::prefix('demo')->group(function () {
    Route::get('/', fn () => response()->json([
        'routes' => [
            'GET  /demo/users        — list 20 users (queries)',
            'GET  /demo/users/{id}   — single user lookup',
            'GET  /demo/slow         — slow endpoint (~750ms)',
            'GET  /demo/boom         — throws an unhandled exception',
            'GET  /demo/handled      — catches and reports an exception',
            'GET  /demo/cache        — cache get/put/forget',
            'GET  /demo/job          — dispatch a queued job (ok|fail)',
            'GET  /demo/mail         — send a mail',
            'GET  /demo/notify       — send a notification',
            'GET  /demo/http         — outgoing HTTP request',
            'GET  /demo/log          — emit logs at every level',
            'GET  /demo/n-plus-one   — classic N+1 query pattern',
        ],
    ]));

    Route::get('users', fn () => User::query()->limit(20)->get());

    Route::get('users/{id}', fn (int $id) => User::query()->findOrFail($id));

    Route::get('slow', function () {
        usleep(750_000);
        DB::table('users')->count();

        return ['ok' => true, 'elapsed_ms' => 750];
    });

    Route::get('boom', function () {
        throw new RuntimeException('Intentional boom from /demo/boom');
    });

    Route::get('handled', function () {
        try {
            throw new LogicException('Handled exception demo');
        } catch (Throwable $e) {
            report($e);

            return ['reported' => true, 'message' => $e->getMessage()];
        }
    });

    Route::get('cache', function () {
        Cache::put('demo:ping', now()->toIso8601String(), 60);
        $value = Cache::get('demo:ping');
        Cache::remember('demo:expensive', 30, fn () => ['computed' => microtime(true)]);
        Cache::forget('demo:ping');

        return ['ping' => $value];
    });

    Route::get('job', function () {
        $mode = request('mode', 'ok');
        DemoJob::dispatch($mode);

        return ['dispatched' => true, 'mode' => $mode];
    });

    Route::get('mail', function () {
        Mail::to('dev@example.com')->send(new DemoMail('hello from /demo/mail'));

        return ['sent' => true];
    });

    Route::get('notify', function () {
        $user = User::query()->first() ?? User::factory()->create();
        Notification::send($user, new DemoNotification);

        return ['notified' => $user->id];
    });

    Route::get('http', function () {
        $res = Http::timeout(5)->get('https://httpbin.org/get', ['from' => 'nightowl-test']);

        return ['status' => $res->status(), 'url' => (string) $res->effectiveUri()];
    });

    Route::get('log', function () {
        Log::debug('demo debug', ['ctx' => 'debug']);
        Log::info('demo info', ['ctx' => 'info']);
        Log::warning('demo warning', ['ctx' => 'warning']);
        Log::error('demo error', ['ctx' => 'error']);

        return ['logged' => ['debug', 'info', 'warning', 'error']];
    });

    Route::get('n-plus-one', function () {
        $users = User::query()->limit(10)->get();
        foreach ($users as $user) {
            DB::table('users')->where('id', $user->id)->value('email');
        }

        return ['count' => $users->count()];
    });
});
