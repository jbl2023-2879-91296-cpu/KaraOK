<?php

declare(strict_types=1);

namespace KaraOK\Admin\Services;

final class AnalysisService
{
    /** @param list<array<string, mixed>> $tables
     *  @param array<string, list<array<string, mixed>>> $columnsByTable
     *  @param array<string, list<array<string, mixed>>> $indexesByTable
     *  @return list<array<string, string>>
     */
    public function analyze(array $tables, array $columnsByTable, array $indexesByTable): array
    {
        $findings = [];
        foreach ($tables as $table) {
            $name = (string) $table['name'];
            $columns = $columnsByTable[$name] ?? [];
            $indexes = $indexesByTable[$name] ?? [];
            if (!array_filter($columns, static fn (array $c): bool => ($c['column_key'] ?? '') === 'PRI')) {
                $findings[] = $this->finding('high', 'confirmed', $name, 'No primary key', 'Add one only after reviewing application expectations and existing duplicates.');
            }
            if ($indexes === []) {
                $findings[] = $this->finding('medium', 'confirmed', $name, 'No indexes reported', 'Review common filters and joins before proposing an index.');
            }
            if ((int) ($table['estimated_rows'] ?? 0) === 0) {
                $findings[] = $this->finding('info', 'inferred', $name, 'Table appears empty', 'MySQL row counts are estimates; confirm with an approved count if needed.');
            }
            if ((int) ($table['estimated_rows'] ?? 0) >= 100000) {
                $findings[] = $this->finding('medium', 'inferred', $name, 'Large table', 'Avoid broad searches and review indexing before running expensive reports.');
            }
            foreach ($columns as $column) {
                if (in_array(strtolower((string) ($column['data_type'] ?? '')), ['longtext', 'longblob', 'mediumblob'], true)) {
                    $findings[] = $this->finding('low', 'confirmed', $name . '.' . $column['name'], 'Large-value column', 'Verify this value belongs in the database and is not selected unnecessarily.');
                }
            }
        }
        return $findings;
    }

    /** @return array<string, string> */
    private function finding(string $severity, string $confidence, string $scope, string $title, string $recommendation): array
    {
        return compact('severity', 'confidence', 'scope', 'title', 'recommendation');
    }
}
