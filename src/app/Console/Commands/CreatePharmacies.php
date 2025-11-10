<?php

namespace App\Console\Commands;

use App\Models\Address;
use App\Models\Pharmacie;
use App\Services\GouvAddressApi;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class CreatePharmacies extends Command
{

    public const string PHARMACIES_TABLE = 'pharmacies';

    /**
     * The name and signature of the console command app:normalize
     * optional cache-path=
     *
     * @var string
     */
    protected $signature = 'app:create-pharmacies';



    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Command description';

    private GouvAddressApi $gouvAddressApi;

    /**
     * Execute the console command.
     */

    public function __construct(GouvAddressApi $gouvAddressApi, ?string $cachePath = null)
    {
        parent::__construct();
        $this->gouvAddressApi = $gouvAddressApi;
        $this->gouvAddressApi->setCachePath($cachePath);

    }


    public function handle()
    {
        $this->createPhamaciesTableIfNotExists();

        $start = 0;
        $limit = 100;

        do {
            $query = "
                SELECT
                    *
                FROM raw_rpps
                WHERE
                    libelle_role =\"Titulaire d'officine\"
                LIMIT $limit OFFSET $start
            ";
            $results = DB::select($query);
            $count = count($results);
            $start += $limit;
            foreach ($results as $data) {
                $this->createPharmacieRecord($data);
            }
            
        } while ($count > 0);
    }

    private function createPharmacieRecord($data)
    {
        $existing = \DB::table(self::PHARMACIES_TABLE)
            ->where('finess', $data->numero_finess_site)
            ->first();
        if ($existing) {
            $this->info("Pharmacie with finess" . $data->numero_finess_site . " already exists. Skipping.");
            return;
        }

        $pharmacie = new Pharmacie();
        $pharmacie->finess = $data->numero_finess_site;
        $pharmacie->name = $data->raison_sociale_site;
        $pharmacie->siret = $data->numero_siret_site;
        $pharmacie->siren = $data->numero_siren_site;
        $pharmacie->save();

        $this->info("Pharmacie with finess " . $data->numero_finess_site . " created.");
    }

    private function createPhamaciesTableIfNotExists()
    {

        // check if pharmacies table exists, if not create it
        $pharmaciesTableExists = \Schema::hasTable(self::PHARMACIES_TABLE);
        if ($pharmaciesTableExists) {
            $this->info("Pharmacies table already exists.");
            return;
        }

        $query = "
            CREATE TABLE IF NOT EXISTS " . self::PHARMACIES_TABLE . " (
                id INT AUTO_INCREMENT PRIMARY KEY,
                finess VARCHAR(255),
                siret VARCHAR(255),
                siren VARCHAR(255),
                name VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_finess (finess),
                inDEX idx_siret (siret),
                INDEX idx_siren (siren)
            )
        ";
        \DB::statement($query);
        $this->info("Pharmacies table created.");
    }
}
