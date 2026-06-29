<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

final class DemoMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public readonly string $body = 'Hello from NightOwl test') {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'NightOwl Test Email');
    }

    public function content(): Content
    {
        return new Content(htmlString: '<p>'.e($this->body).'</p>');
    }
}
