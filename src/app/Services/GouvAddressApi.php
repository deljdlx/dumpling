<?php

namespace App\Services;


class GouvAddressApi
{

    private $baseUrl = 'https://api-adresse.data.gouv.fr/';
    private ?string $cachePath = null;


    public function __construct(?string $cachePath = null)
    {
        if ($cachePath === null) {
            $cachePath = sys_get_temp_dir() . '/gouv_address_api_cache';
        }

        if ($cachePath) {
            $this->cachePath = $cachePath;
            $this->ensureCachePathExists();
        } else {
            throw new \Exception("Cache path must be provided");
        }

        $this->cachePath = $cachePath;
    }

    public function setCachePath(?string $cachePath)
    {
        if ($cachePath === null) {
            $cachePath = sys_get_temp_dir() . '/gouv_address_api_cache';
        }

        $this->cachePath = $cachePath;
        $this->ensureCachePathExists();
    }

    private function ensureCachePathExists()
    {
        if (!file_exists($this->cachePath)) {
            mkdir($this->cachePath, 0777, true);
        }
    }



    public function search(
        $address0,
        $address1 = null,
        $postcode = null,
        $city = null,
    ) {
        $params = [];
        $params['q'] = $address0;
        if ($address1) {
            $params['q'] .= ' ' . $address1;
        }
        if ($postcode) {
            $params['q'] .= ' ' . $postcode;
        }
        if ($city) {
            $params['q'] .= ' ' . $city;
        }

        return $this->httpGet(
            $this->baseUrl . 'search/',
            $params
        );
    }


    private function cacheKey($url, $params = [])
    {
        ksort($params);
        // slugify the url and params to create a unique filename
        $url = str_replace(['http://', 'https://', '/', '?', '&', '='], '_', $url);
        $paramString = http_build_query($params);
        $paramString = str_replace(['/', '?', '&', '='], '_', $paramString);
        return $this->cachePath . '/' . md5($url . '_' . $paramString) . '.cache';
    }



    private function httpGet($url, $params = [])
    {

        if ($this->cachePath) {
            $cacheFile = $this->cacheKey($url, $params);
            if (file_exists($cacheFile)) {
                $cachedResponse = file_get_contents($cacheFile);
                return json_decode($cachedResponse, true);
            }
        }

        $queryString = http_build_query($params);
        $fullUrl = $url . '?' . $queryString;

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $fullUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);

        $response = curl_exec($ch);
        curl_close($ch);

        $data = json_decode($response, true);
        if ($data === null) {
            throw new \Exception("Failed to decode JSON response from Gouv Address API");
        }

        if(!count($data['features'])) {
            throw new \Exception("No features found for address: " . $fullUrl);
        }


        if ($this->cachePath) {
            file_put_contents($cacheFile, $response);
        }


        return $data;
    }
}
