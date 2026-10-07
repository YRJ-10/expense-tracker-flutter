import { Env, ParsedTransaction } from './types';

export class FirestoreClient {
  private projectId: string;
  private clientEmail: string;
  private privateKey: string;
  private cachedToken: { token: string; expiresAt: number } | null = null;

  constructor(env: Env) {
    this.projectId = env.FIREBASE_PROJECT_ID;
    this.clientEmail = env.FIREBASE_CLIENT_EMAIL;
    // Replace escaped newlines if any
    this.privateKey = (env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  }

  public async getAccessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedToken && this.cachedToken.expiresAt > now + 60) {
      return this.cachedToken.token;
    }

    const header = { alg: 'RS256', typ: 'JWT' };
    const payload = {
      iss: this.clientEmail,
      scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      exp: now + 3600,
      iat: now,
    };

    const b64Header = this.base64UrlEncode(JSON.stringify(header));
    const b64Payload = this.base64UrlEncode(JSON.stringify(payload));
    const unsignedToken = `${b64Header}.${b64Payload}`;

    const signature = await this.signJwt(unsignedToken, this.privateKey);
    const signedJwt = `${unsignedToken}.${signature}`;

    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: signedJwt,
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Failed to obtain Google access token: ${res.status} ${errText}`);
    }

    const data = (await res.json()) as { access_token: string; expires_in: number };
    this.cachedToken = {
      token: data.access_token,
      expiresAt: now + data.expires_in,
    };
    return data.access_token;
  }

  private base64UrlEncode(str: string): string {
    const b64 = btoa(unescape(encodeURIComponent(str)));
    return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  private base64UrlEncodeBuffer(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  private async signJwt(content: string, pemKey: string): Promise<string> {
    const cleanPem = pemKey
      .replace(/-----BEGIN PRIVATE KEY-----/g, '')
      .replace(/-----END PRIVATE KEY-----/g, '')
      .replace(/\s+/g, '');

    const binaryDer = Uint8Array.from(atob(cleanPem), (c) => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey(
      'pkcs8',
      binaryDer.buffer,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign']
    );

    const encoder = new TextEncoder();
    const data = encoder.encode(content);
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, data);
    return this.base64UrlEncodeBuffer(signature);
  }

  // Convert plain JS object to Firestore Value map
  private toFirestoreFields(obj: Record<string, any>): Record<string, any> {
    const fields: Record<string, any> = {};
    for (const [key, val] of Object.entries(obj)) {
      if (val === null || val === undefined) {
        fields[key] = { nullValue: null };
      } else if (typeof val === 'string') {
        fields[key] = { stringValue: val };
      } else if (typeof val === 'number') {
        if (Number.isInteger(val)) {
          fields[key] = { integerValue: val.toString() };
        } else {
          fields[key] = { doubleValue: val };
        }
      } else if (typeof val === 'boolean') {
        fields[key] = { booleanValue: val };
      } else if (val instanceof Date) {
        fields[key] = { timestampValue: val.toISOString() };
      } else if (Array.isArray(val)) {
        fields[key] = {
          arrayValue: {
            values: val.map((item) => this.toFirestoreFields({ _: item })._),
          },
        };
      } else if (typeof val === 'object') {
        fields[key] = { mapValue: { fields: this.toFirestoreFields(val) } };
      }
    }
    return fields;
  }

  // Parse Firestore fields back to JS Object
  private fromFirestoreFields(fields: Record<string, any>): Record<string, any> {
    const result: Record<string, any> = {};
    for (const [key, val] of Object.entries(fields)) {
      if ('stringValue' in val) result[key] = val.stringValue;
      else if ('integerValue' in val) result[key] = parseInt(val.integerValue, 10);
      else if ('doubleValue' in val) result[key] = val.doubleValue;
      else if ('booleanValue' in val) result[key] = val.booleanValue;
      else if ('timestampValue' in val) result[key] = val.timestampValue;
      else if ('nullValue' in val) result[key] = null;
      else if ('mapValue' in val) result[key] = this.fromFirestoreFields(val.mapValue.fields || {});
    }
    return result;
  }

  private get baseUrl(): string {
    return `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents`;
  }

  async getDocument(collection: string, docId: string): Promise<Record<string, any> | null> {
    const token = await this.getAccessToken();
    const res = await fetch(`${this.baseUrl}/${collection}/${docId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) return null;
    if (!res.ok) {
      throw new Error(`Get doc error: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as any;
    return this.fromFirestoreFields(data.fields || {});
  }

  async setDocument(collection: string, docId: string, data: Record<string, any>): Promise<void> {
    const token = await this.getAccessToken();
    const fields = this.toFirestoreFields(data);
    const res = await fetch(`${this.baseUrl}/${collection}/${docId}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    });
    if (!res.ok) {
      throw new Error(`Set doc error: ${res.status} ${await res.text()}`);
    }
  }

  async queryCollection(collection: string, field: string, operator: string, value: any): Promise<Array<{ id: string; data: Record<string, any> }>> {
    const token = await this.getAccessToken();
    const query = {
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: operator, // e.g. "EQUAL"
            value: this.toFirestoreFields({ _: value })._,
          },
        },
      },
    };

    const res = await fetch(`${this.baseUrl}:runQuery`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(query),
    });

    if (!res.ok) {
      throw new Error(`Query error: ${res.status} ${await res.text()}`);
    }

    const items = (await res.json()) as any[];
    const results: Array<{ id: string; data: Record<string, any> }> = [];
    for (const item of items) {
      if (item.document) {
        const pathParts = item.document.name.split('/');
        const id = pathParts[pathParts.length - 1];
        results.push({
          id,
          data: this.fromFirestoreFields(item.document.fields || {}),
        });
      }
    }
    return results;
  }

  // Cari wallet berdasarkan userId & nomor rekening / nama bank
  async findMatchingWallet(userId: string, bank: string, accountNumber?: string): Promise<{ id: string; data: Record<string, any> } | null> {
    const wallets = await this.queryCollection('wallets', 'user_id', 'EQUAL', userId);
    if (wallets.length === 0) return null;

    // Prioritas 1: Cocokkan nomor rekening (misal 0182)
    if (accountNumber) {
      const matchAcc = wallets.find((w) => {
        const acc = (w.data.account_number || '').toString();
        return acc.includes(accountNumber) || accountNumber.includes(acc);
      });
      if (matchAcc) return matchAcc;
    }

    // Prioritas 2: Cocokkan nama bank (MANDIRI)
    const matchBank = wallets.find((w) => {
      const name = (w.data.name || '').toUpperCase();
      const bName = (w.data.bank_name || '').toUpperCase();
      return name.includes(bank) || bName.includes(bank);
    });
    if (matchBank) return matchBank;

    // Fallback: wallet default pertama
    return wallets[0];
  }

  // Deduplikasi: cek apakah transaksi dengan reference_id atau message_id sudah tersimpan
  async isTransactionDuplicate(userId: string, referenceId: string, messageId: string): Promise<boolean> {
    // Cek di collection transactions
    const byRef = await this.queryCollection('transactions', 'reference_id', 'EQUAL', referenceId);
    if (byRef.some((t) => t.data.user_id === userId)) return true;

    const byMsg = await this.queryCollection('transactions', 'message_id', 'EQUAL', messageId);
    if (byMsg.some((t) => t.data.user_id === userId)) return true;

    return false;
  }

  // Simpan transaksi dan update saldo wallet secara otomatis
  async saveParsedTransaction(userId: string, tx: ParsedTransaction): Promise<boolean> {
    const isDup = await this.isTransactionDuplicate(userId, tx.referenceId, tx.messageId);
    if (isDup) {
      console.log(`Transaction ${tx.referenceId} (${tx.messageId}) already exists. Skipping.`);
      return false;
    }

    const wallet = await this.findMatchingWallet(userId, tx.bank, tx.accountNumber);
    if (!wallet) {
      console.log(`No matching wallet found for user ${userId}. Skipping.`);
      return false;
    }

    // CUTOFF DATE: Jika transaksi terjadi SEBELUM tanggal saldo awal dibuat, buang/abaikan!
    const walletCreatedAt = wallet.data.created_at ? new Date(wallet.data.created_at).getTime() : 0;
    const txTime = new Date(tx.date).getTime();
    if (txTime < walletCreatedAt) {
      console.log(`Transaction ${tx.referenceId} date (${tx.date}) is before wallet initial balance date (${wallet.data.created_at}). Discarded.`);
      return false;
    }

    const walletId = wallet.id;
    const txId = `tx_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;

    const txDoc = {
      id: txId,
      user_id: userId,
      wallet_id: walletId,
      amount: tx.amount,
      type: tx.type, // 'income' | 'expense'
      category: tx.category,
      description: tx.description,
      transaction_date: tx.date,
      created_at: new Date().toISOString(),
      reference_id: tx.referenceId,
      message_id: tx.messageId,
      source: 'GMAIL_AUTO_SYNC',
      bank_name: tx.bank,
      is_auto_synced: true,
    };

    await this.setDocument('transactions', txId, txDoc);

    // Update wallet balance jika wallet ditemukan
    if (wallet) {
      const currentBalance = (wallet.data.balance as number) || 0;
      const newBalance = tx.type === 'income' ? currentBalance + tx.amount : currentBalance - tx.amount;
      await this.setDocument('wallets', wallet.id, {
        ...wallet.data,
        balance: newBalance,
        updated_at: new Date().toISOString(),
      });
    }

    // Auto-reduce Debt jika transaksi ini adalah pembayaran kartu kredit
    if (tx.category === 'Kartu Kredit' || /kartu kredit|credit card/i.test(tx.description)) {
      try {
        const debts = await this.queryCollection('debts', 'user_id', 'EQUAL', userId);
        const matchDebt = debts.find((d) => 
          !d.data.is_paid && 
          ((d.data.person_name || '').toLowerCase().includes('kartu kredit') ||
           (d.data.person_name || '').toLowerCase().includes('credit card') ||
           d.data.type === 'borrowed')
        );
        if (matchDebt) {
          const originalAmt = (matchDebt.data.amount as number) || 0;
          const currentRemaining = typeof matchDebt.data.remaining_amount === 'number'
            ? matchDebt.data.remaining_amount
            : originalAmt;
          const currentPaid = (matchDebt.data.paid_amount as number) || 0;

          const newRemaining = Math.max(0, currentRemaining - tx.amount);
          const newPaid = currentPaid + tx.amount;
          const isPaid = newRemaining <= 0;

          await this.setDocument('debts', matchDebt.id, {
            ...matchDebt.data,
            remaining_amount: newRemaining,
            paid_amount: newPaid,
            is_paid: isPaid,
            last_payment_date: tx.date,
            updated_at: new Date().toISOString(),
          });
          console.log(`Auto-updated debt ${matchDebt.id}: remaining was ${currentRemaining}, now ${newRemaining}`);
        }
      } catch (err) {
        console.error('Error auto-updating debt for credit card payment:', err);
      }
    }

    return true;
  }

  // Ambil semua dokumen dalam suatu collection (misal: users untuk pengecekan reminder)
  async getAllDocuments(collection: string): Promise<Array<{ id: string; data: Record<string, any> }>> {
    const token = await this.getAccessToken();
    const res = await fetch(`${this.baseUrl}/${collection}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      console.error(`List documents error (${res.status}):`, await res.text());
      return [];
    }
    const data = (await res.json()) as { documents?: Array<{ name: string; fields?: Record<string, any> }> };
    if (!data.documents) return [];
    return data.documents.map((doc) => {
      const parts = doc.name.split('/');
      const id = parts[parts.length - 1];
      return {
        id,
        data: this.fromFirestoreFields(doc.fields || {}),
      };
    });
  }
}
