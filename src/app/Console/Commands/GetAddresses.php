<?php

namespace App\Console\Commands;

use App\Models\RawAddress;
use App\Services\GouvAddressApi;
use Illuminate\Console\Command;

class GetAddresses extends Command
{
    /**
     * The name and signature of the console command app:normalize
     * optional cache-path=
     *
     * @var string
     */
    protected $signature = 'app:get-adresses {--cache-path=}';



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
        //get cache-path option
        $cachePath = $this->option('cache-path');
        if ($cachePath) {
            $this->gouvAddressApi->setCachePath($cachePath);
        }

        $countQuery = "
            SELECT
                COUNT(*) as count
            FROM raw_rpps
            WHERE
                libelle_role =\"Titulaire d'officine\"
        ";
        $countResult = \DB::select($countQuery);
        
        
        $totalCount = $countResult[0]->count;
        $startTime=microtime(true);
        $computedCount=0;

        /*
            -- better join query, but have to select only the needed fields
            SELECT
                rpps.*,
                finess.*
            FROM rpps
            LEFT JOIN finess ON
                rpps.numero_finess_site=finess.finess
            WHERE
                libelle_role ="Titulaire d'officine"
        */

        $start = 0;
        $limit = 10;


        do {
            $count = $this->batch(
                "
                    SELECT
                        *
                    FROM raw_rpps
                    WHERE
                        libelle_role =\"Titulaire d'officine\"
                ",
                $start,
                $limit
            )->each(function($item)
                use ($totalCount, &$computedCount, $startTime) {
                $address= $item->numero_voie_coord_structure . ' ' .
                    $item->code_type_de_voie_coord_structure. ' ' .
                    $item->libelle_voie_coord_structure;

                $addressModel = RawAddress::where('rpps', $item->identifiant_pp)->first();

                if($addressModel) {
                    $computedCount++;
                    $this->info("Address for RPPS " . $item->identifiant_pp . " already exists, skipping API call.");
                    return;
                }

                $tryCount = 0;
                $response = null;
                do {
                    try {

                        $response = $this->gouvAddressApi->search(
                            $address,
                            null,
                            $item->code_postal_coord_structure,
                            $item->libelle_commune_coord_structure
                        );

                        $addressModel = new RawAddress();
                        $addressModel->rpps = $item->identifiant_pp;
                        $addressModel->finess = $item->numero_finess_site;
                        $addressModel->data = json_encode($response, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
                        $addressModel->save();

                        $response = json_decode($addressModel->data, true);
                    }
                    catch (\Exception $e) {
                        $this->error("Failed to decode JSON for RPPS " . $item->identifiant_pp . ": " . $e->getMessage());
                        sleep(1);
                        $response = null;
                        $tryCount++;

                        if($tryCount >= 5) {
                            $this->error("Max retries reached for RPPS " . $item->identifiant_pp . ", skipping.");
                        }
                    }
                } while($response === null && $tryCount < 5);
                

                $elapsedTimeInSeconds = microtime(true) - $startTime;
                $computedCount++;
                $remainngTimeInSeconds = ($elapsedTimeInSeconds / $computedCount) * ($totalCount - $computedCount);
                $computedPerSecond = $computedCount / $elapsedTimeInSeconds;

                $this->info(
                    "Processed $computedCount / $totalCount " .
                    " (" . round(($computedCount / $totalCount) * 100, 2) . "%) " .
                    " - Elapsed: " . gmdate("H:i:s", (int)$elapsedTimeInSeconds) .
                    " - Remaining: " . gmdate("H:i:s", (int)$remainngTimeInSeconds) .
                    " - Speed: " . round($computedPerSecond, 2) . " items/s"
                );
                

                $maxPerSeconds = 40;
                $delayMicroseconds = (1 / $maxPerSeconds) * 1000000;
                usleep($delayMicroseconds);
            })->count();

            $start += $count;

        } while ($count > 0);
    }

    private function batch($query, $start = 0, $limit = 10) {
        $results = \DB::select(
            $query . ' LIMIT ' . $start . ', ' . $limit
        );
        return collect($results);

    }
}
