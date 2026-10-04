import { Env } from './types';

export interface GmailMessageItem {
  id: string;
  from: string;
  subject: string;
  date: string;
  body: string; // decoded HTML / text
}

export class GmailClient {
  private clientId: string;
  private clientSecret: string;

  constructor(env: Env) {
    this.clientId = env.GOOGLE_CLIENT_ID;
    this.clientSecret = env.GOOGLE_CLIENT_SECRET;
  }

  async refreshAccessToken(refreshToken: string): Promise<string> {
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.clientId,
        client_secret: this.clientSecret,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Failed to refresh Google token: ${res.status} ${err}`);
    }

    const data = (await res.json()) as { access_token: string };
    return data.access_token;
  }

  async listBankMessages(accessToken: string, query = 'from:bankmandiri.co.id'): Promise<string[]> {
    const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(query)}&maxResults=25`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!res.ok) {
      throw new Error(`Gmail list messages error: ${res.status} ${await res.text()}`);
    }

    const data = (await res.json()) as { messages?: Array<{ id: string }> };
    return (data.messages || []).map((m) => m.id);
  }

  async getMessage(accessToken: string, messageId: string): Promise<GmailMessageItem | null> {
    const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=full`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!res.ok) {
      return null;
    }

    const data = (await res.json()) as any;
    const headers = data.payload?.headers || [];
    let from = '';
    let subject = '';
    let date = '';

    for (const h of headers) {
      const name = h.name.toLowerCase();
      if (name === 'from') from = h.value;
      if (name === 'subject') subject = h.value;
      if (name === 'date') date = h.value;
    }

    const body = this.extractBody(data.payload);

    return {
      id: messageId,
      from,
      subject,
      date,
      body,
    };
  }

  private extractBody(payload: any): string {
    if (!payload) return '';

    // Direct body data
    if (payload.body?.data) {
      return this.decodeBase64Url(payload.body.data);
    }

    // Parts (multipart/alternative or multipart/mixed)
    if (payload.parts && Array.isArray(payload.parts)) {
      // Prioritaskan text/html
      for (const part of payload.parts) {
        if (part.mimeType === 'text/html' && part.body?.data) {
          return this.decodeBase64Url(part.body.data);
        }
      }

      // Alternatif text/plain
      for (const part of payload.parts) {
        if (part.mimeType === 'text/plain' && part.body?.data) {
          return this.decodeBase64Url(part.body.data);
        }
      }

      // Rekursif jika ada nested parts
      for (const part of payload.parts) {
        const nested = this.extractBody(part);
        if (nested) return nested;
      }
    }

    return '';
  }

  private decodeBase64Url(input: string): string {
    let base64 = input.replace(/-/g, '+').replace(/_/g, '/');
    while (base64.length % 4) {
      base64 += '=';
    }
    try {
      const decoded = atob(base64);
      return decodeURIComponent(escape(decoded));
    } catch {
      return atob(base64);
    }
  }
}
