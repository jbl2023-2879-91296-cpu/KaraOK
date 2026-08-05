<?php

declare(strict_types=1);

namespace KaraOK\Admin\Api;

use KaraOK\Admin\Config\Environment;

final class AdminApiClient
{
    private readonly string $baseUrl;
    private readonly string $key;

    public function __construct(private readonly Environment $env)
    {
        $this->baseUrl = rtrim($env->get('ADMIN_API_BASE_URL'), '/');
        $this->key = $env->get('ADMIN_API_KEY');
        if ($this->baseUrl === '' || strlen($this->key) < 32) {
            throw new AdminApiException('The Data Administration API URL or key is not configured.');
        }
        $isLocalHttp = preg_match('#^http://(127\.0\.0\.1|localhost)(:\d+)?(?:/|$)#i', $this->baseUrl) === 1;
        if (!str_starts_with(strtolower($this->baseUrl), 'https://') && !$isLocalHttp) {
            throw new AdminApiException('The Data Administration API must use HTTPS outside localhost.');
        }
    }

    /** @return array<string, mixed> */
    public function health(): array { return $this->request('GET', '/health'); }
    /** @return list<array<string, mixed>> */
    public function tables(): array { return $this->request('GET', '/tables'); }
    /** @return array<string, mixed> */
    public function table(string $table): array { return $this->request('GET', '/tables/' . rawurlencode($table)); }
    /** @param array<string, mixed> $query @return array<string, mixed> */
    public function records(string $table, array $query = []): array
    {
        return $this->request('GET', '/tables/' . rawurlencode($table) . '/records', $query);
    }
    /** @param array<string, mixed> $values @return array<string, mixed> */
    public function create(string $table, array $values): array
    {
        return $this->request('POST', '/tables/' . rawurlencode($table) . '/records', [], $values);
    }
    /** @param array<string, mixed> $values @return array<string, mixed> */
    public function update(string $table, string $id, array $values): array
    {
        return $this->request('PATCH', '/tables/' . rawurlencode($table) . '/records/' . rawurlencode($id), [], $values);
    }
    /** @return array<string, mixed> */
    public function delete(string $table, string $id): array
    {
        return $this->request('DELETE', '/tables/' . rawurlencode($table) . '/records/' . rawurlencode($id), [], [
            'confirmation' => "DELETE {$table}:{$id}",
        ]);
    }
    /** @return list<array<string, mixed>> */
    public function relationships(): array { return $this->request('GET', '/relationships'); }
    /** @return array<string, mixed> */
    public function analytics(): array { return $this->request('GET', '/analytics'); }

    /** @param array<string, mixed> $query
     *  @param array<string, mixed>|null $body
     *  @return mixed
     */
    private function request(string $method, string $path, array $query = [], ?array $body = null): mixed
    {
        $url = $this->baseUrl . $path;
        if ($query !== []) {
            $url .= '?' . http_build_query($query);
        }
        $handle = curl_init($url);
        if ($handle === false) {
            throw new AdminApiException('Unable to initialize the Data Administration API request.');
        }
        $headers = [
            'Accept: application/json',
            'Authorization: Bearer ' . $this->key,
            'X-KaraOK-Admin-Actor: ' . substr((string) ($_SESSION['admin']['username'] ?? 'local-admin'), 0, 64),
        ];
        $options = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_CONNECTTIMEOUT => max(2, $this->env->int('ADMIN_API_CONNECT_TIMEOUT', 5)),
            CURLOPT_TIMEOUT => max(5, $this->env->int('ADMIN_API_TIMEOUT', 20)),
            CURLOPT_SSL_VERIFYPEER => $this->env->bool('ADMIN_API_VERIFY_TLS', true),
            CURLOPT_SSL_VERIFYHOST => $this->env->bool('ADMIN_API_VERIFY_TLS', true) ? 2 : 0,
        ];
        if ($body !== null) {
            $encoded = json_encode($body, JSON_THROW_ON_ERROR);
            $headers[] = 'Content-Type: application/json';
            $options[CURLOPT_HTTPHEADER] = $headers;
            $options[CURLOPT_POSTFIELDS] = $encoded;
        }
        curl_setopt_array($handle, $options);
        $response = curl_exec($handle);
        $curlError = curl_error($handle);
        $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        curl_close($handle);
        if ($response === false) {
            throw new AdminApiException('Could not reach the Data Administration API: ' . $curlError);
        }
        try {
            $decoded = json_decode((string) $response, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new AdminApiException('The Data Administration API returned an invalid response.', $status);
        }
        if ($status < 200 || $status >= 300) {
            $message = is_array($decoded) && is_string($decoded['error'] ?? null)
                ? $decoded['error']
                : 'The Data Administration API rejected the request.';
            throw new AdminApiException($message, $status);
        }
        return $decoded;
    }
}
