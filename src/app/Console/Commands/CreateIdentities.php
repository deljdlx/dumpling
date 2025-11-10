<?php

namespace App\Console\Commands;

use App\Models\Identity;
use App\Models\RawAddress;
use App\Services\GouvAddressApi;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class CreateIdentities extends Command
{

    public const string IDENTITIES_TABLE = 'identities';
    public const string RELATION_TABLE = 'pharmacies_identities';


    /**
     * The name and signature of the console command app:normalize
     * optional cache-path=
     *
     * @var string
     */
    protected $signature = 'app:create-identies';



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



    public function handle()
    {   
        $this->createIdentitiesTableIfNotExists();
        $this->createRelationTableIfNotExists();

        $start = 0;
        $limit = 100;

        do {
            $query = "
                SELECT
                    raw_rpps.*
                FROM raw_rpps
                JOIN addresses
                    ON addresses.finess = raw_rpps.numero_finess_site
                LIMIT $limit OFFSET $start
            ";
            $results = DB::select($query);
            $count = count($results);
            $start += $limit;

            foreach ($results as $data) {
                $identity = $this->createIdentityRecord($data);
            }


            
        } while ($count > 0);
    }

    private function createIdentityRecord($data)
    {

        $pharmacy = DB::table(CreatePharmacies::PHARMACIES_TABLE)
            ->where('finess', $data->numero_finess_site)
            ->first();

        // find Indentity by rpps
        $identity = DB::table(self::IDENTITIES_TABLE)
            ->where('rpps', $data->identifiant_pp)
            ->first();
        if ($identity) {
            $this->info("Identity with RPPS " . $data->identifiant_pp . " already exists. Skipping.");
            return;
        }

        $identity = new Identity();
        $identity->rpps = $data->identifiant_pp;
        $identity->civility = $data->libelle_civilite;
        $identity->first_name = $data->prenom_d_exercice;
        $identity->last_name = $data->nom_d_exercice;
        $identity->role = $data->libelle_role;


        $identity->save();

        $relationId = DB::table(self::RELATION_TABLE)
            ->insertGetId([
                'pharmacy_id' => $pharmacy->id,
                'identity_id' => $identity->id,
            ]);

        $this->info("Identity with RPPS " . $data->identifiant_pp . " created with relation ID $relationId.");
        return $identity;

    }


    private function createRelationTableIfNotExists()
    {
        if (\Schema::hasTable(self::RELATION_TABLE)) {
            $this->info("Relation table already exists.");
            return;
        }

        $query = "
            CREATE TABLE IF NOT EXISTS " . self::RELATION_TABLE . " (
                id INT AUTO_INCREMENT PRIMARY KEY,
                pharmacy_id INT,
                identity_id INT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_pharmacy_id (pharmacy_id),
                INDEX idx_identity_id (identity_id)
            )
        ";
        \DB::statement($query);
        $this->info("Relation table created.");
    }

    private function createIdentitiesTableIfNotExists()
    {
        // check if pharmacies table exists, if not create it
        $pharmaciesTableExists = \Schema::hasTable(self::IDENTITIES_TABLE);
        if ($pharmaciesTableExists) {
            $this->info("Identities table already exists.");
            return;
        }

        $query = "
            CREATE TABLE IF NOT EXISTS " . self::IDENTITIES_TABLE . " (
                id INT AUTO_INCREMENT PRIMARY KEY,
                rpps VARCHAR(255) UNIQUE NULL,
                civility VARCHAR(10),
                first_name VARCHAR(255),
                last_name VARCHAR(255),
                role VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_rpps (rpps),
                INDEX first_name_idx (first_name),
                INDEX last_name_idx (last_name),
                INDEX idx_civility (civility),
                INDEX idx_role (role)

            )
        ";
        \DB::statement($query);
        $this->info("Identities table created.");
    }
}

