<?php

namespace App\Console\Commands;

use App\Models\Address;
use App\Models\RawAddress;
use App\Services\GouvAddressApi;
use Illuminate\Console\Command;

class NormalizeAddresses extends Command
{
    /**
     * The name and signature of the console command app:normalize
     * optional cache-path=
     *
     * @var string
     */
    protected $signature = 'app:normalize-adresses';



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
        $start = 0;
        $limit = 10;
        $this->createAddressesTableIfNotExists();

        do {
            $query = "
                SELECT
                    *
                FROM raw_addresses
                LIMIT $start, $limit
            ";
            $results = RawAddress::hydrate(\DB::select($query));
            $count = count($results);
            $start += $limit;
            foreach ($results as $rawAddress) {
                $this->normalizeAddress($rawAddress);
            }
            
        } while ($count > 0);
    }

    private function normalizeAddress(RawAddress $rawAddress)
    {
        $json = json_decode($rawAddress->data, true);
        $properties = $json['features'][0]['properties'] ?? null;
        $geometry = $json['features'][0]['geometry'] ?? null;
        if (!$properties || !$geometry) {
            $this->error("Invalid address data for raw address ID " . $rawAddress->id);
            return;
        }


        $gouvId = $properties['id'] ?? null;
        if (!$gouvId) {
            $this->error("No BAN ID found for raw address RPPS " . $rawAddress->rpps);
            dump($json);
            echo __FILE__.':'.__LINE__; exit();
            return;
        }
        

        $address = Address::where('gouv_id', $gouvId)->first();
        if ($address) {
            $this->info("Address with GOUV ID $gouvId already exists. Skipping.");
            return; 
        }
        $address = new Address();
        $address->gouv_id = $gouvId;
        $address->finess = $rawAddress->finess;
        $address->label = $properties['label'] ?? null;
        $address->address = $properties['name'] ?? null;
        $address->postcode = $properties['postcode'] ?? null;
        $address->city = $properties['city'] ?? null;
        $address->json_data = json_encode($json, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        $address->longitude = $geometry['coordinates'][0] ?? null;
        $address->latitude = $geometry['coordinates'][1] ?? null;
        $address->save();
        $this->info("Normalized address saved with GOUV ID $gouvId.");}

    private function createAddressesTableIfNotExists()
    {
        if (\Schema::hasTable('addresses')) {
            $this->info("Addresses table already exists.");
            return;
        }

        $query = "
            CREATE TABLE IF NOT EXISTS addresses (
                id INT AUTO_INCREMENT PRIMARY KEY,
                gouv_id VARCHAR(255) UNIQUE,
                finess VARCHAR(255),
                label VARCHAR(255),
                address VARCHAR(255),
                postcode VARCHAR(20),
                city VARCHAR(255),
                longitude VARCHAR(50),
                latitude VARCHAR(50),
                json_data LONGTEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_gouv_id (gouv_id),
                INDEX idx_finess (finess),
                INDEX idx_postcode (postcode),
                INDEX idx_city (city)
            );
        ";
        \DB::statement($query);
        $this->info("Addresses table created.");
    }
}
