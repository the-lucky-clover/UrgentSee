export class RateLimiterDO {
  state: DurableObjectState;
  
  private readonly windowMs: number = 60 * 60 * 1000;
  private readonly maxDispatchesPerWindow: number = 3;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/check' && request.method === 'POST') {
      return await this.handleRateCheck();
    }

    if (url.pathname === '/reset' && request.method === 'POST') {
      return await this.handleReset();
    }

    return new Response(JSON.stringify({ error: 'NOT_FOUND' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async handleRateCheck(): Promise<Response> {
    const now = Date.now();

    let timestamps: number[] = (await this.state.storage.get<number[]>('timestamps')) || [];

    timestamps = timestamps.filter(ts => now - ts < this.windowMs);

    if (timestamps.length >= this.maxDispatchesPerWindow) {
      const oldestTimestamp = timestamps[0];
      const retryAfterSeconds = Math.ceil((oldestTimestamp + this.windowMs - now) / 1000);

      return new Response(
        JSON.stringify({
          error: 'QUOTA_EXCEEDED',
          message: `Maximum dispatch limit reached (${this.maxDispatchesPerWindow} per hour). Please wait before sending another UrgentSee.`,
          retryAfterSeconds,
          remaining: 0,
        }),
        {
          status: 429,
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': retryAfterSeconds.toString(),
          },
        }
      );
    }

    timestamps.push(now);
    await this.state.storage.put('timestamps', timestamps);

    const remaining = this.maxDispatchesPerWindow - timestamps.length;

    return new Response(
      JSON.stringify({
        success: true,
        remaining,
        windowMs: this.windowMs,
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  private async handleReset(): Promise<Response> {
    await this.state.storage.delete('timestamps');
    return new Response(JSON.stringify({ success: true, message: 'Rate limits cleared.' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
