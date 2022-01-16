#!/bin/bash +x

HOST="62.210.125.202"
PORT=1001
port_client=11223
ip_client="89.234.183.140"
DISABLE_OUTPUT="> /dev/null 2>&1"

ack="ACK"
DEBUG=0

DATA_FOLDER="data"
KEY_FOLDER="$DATA_FOLDER/keys"

# Debug print
function dprint(){
        [ $# -lt 1 ] && echo "Usage: $FUNCNAME MESSAGE" >&2 && return 1
        [ $DEBUG -eq 1 ] && echo $1
}


function send_message() {
	[ $# -lt 2 ] && echo "Usage: $FUNCNAME <host> <port>" >&2 && return 1
	local HOST=$1
	local PORT=$2

	cat | nc -q 0 $HOST $PORT
}

function recv_message() {
	nc -q 0 -lp $port_client
}


function genererUUID() {
	uuid=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')
	echo $uuid
}


function genererRandomCoords(){
	max_int=500
	x=$(od -An -N4 -i < /dev/urandom)
	y=$(od -An -N4 -i < /dev/urandom)
	x=$(echo $(( $x % $max_int )))
	y=$(echo $(( $y % $max_int )))
	echo "$x $y"
}




# Chiffre, $1 = Client
# $1 = IP_Client
# $2 = Fichier
function encrypt(){
        [ $# -lt 2 ] && echo "$# Usage: $FUNCNAME IP MESSAGE" >&2 && return 1
        openssl aes-128-cbc -e -K $(head -c 16 common.key | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 common.key | hexdump -v -e '/1 "%02x"') -out $2.enc -in $2
        result=$(cat $2.enc)
        echo $result
}


# Dechiffre
# $1 = IP_Client
# $2 = fichier
function decrypt(){
        [ $# -lt 2 ] && echo "Usage: $FUNCNAME IP MESSAGE" >&2 && return 1

        openssl aes-128-cbc -d -K $(head -c 16 common.key | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 common.key | hexdump -v -e '/1 "%02x"') -out $2 -in $2.enc
        dechiffre=$(cat $2)
        echo $dechiffre
}

# $1: malade: true/false
function marquerMalade(){
	openssl rsautl -in $DATA_FOLDER/client_data -out donnees_client -inkey $KEY_FOLDER/client.key -decrypt
	data_client=$(cat donnees_client)
	client_uuid=$(echo $data_client | tr -s " " | cut -d " " -f1)
	client_malade=$1
	client_contact=$(echo $data_client | tr -s " " | cut -d " " -f3)
	client_x=$(echo $data_client | tr -s " " | cut -d " " -f4)
	client_y=$(echo $data_client | tr -s " " | cut -d " " -f5)

	echo "$client_uuid $client_malade $client_contact $client_x $client_y" > donnees_client
	openssl rsautl -in donnees_client -out $DATA_FOLDER/client_data -pubin -inkey $KEY_FOLDER/client.pub -encrypt
	rm donnees_client
}


function afficherInfoClient() {
	[[ ! -f $DATA_FOLDER/client_data ]] && echo "Vous devez d'abord lancer l'application une première fois" && exit 1
	openssl rsautl -in $DATA_FOLDER/client_data -out donnees_client -inkey $KEY_FOLDER/client.key -decrypt
	data_client=$(cat donnees_client)
        client_uuid=$(echo $data_client | tr -s " " | cut -d " " -f1)
        client_malade=$(echo $data_client | tr -s " " | cut -d " " -f2)
        client_contact=$(echo $data_client | tr -s " " | cut -d " " -f3)
        client_x=$(echo $data_client | tr -s " " | cut -d " " -f4)
        client_y=$(echo $data_client | tr -s " " | cut -d " " -f5)

	printf "\t\tUUID:\t\t$client_uuid\n"
	printf "\t\tMALADE:\t\t$client_malade\n"
	printf "\t\tCAS CONTACT:\t$client_contact\n"
	printf "\t\tX:\t\t$client_x\n"
	printf "\t\tY:\t\t$client_y\n"
	rm donnees_client

}

function updateGPS() {
	[ $# -lt 1 ] && echo "Erreur, veuillez spécifier les coordonnes sous ce format: x:y" >&2 && return 1
	
	coords=$(echo $1 | sed "s/\:/ /g")

	openssl rsautl -in $DATA_FOLDER/client_data -out donnees_client -inkey $KEY_FOLDER/client.key -decrypt
        data_client=$(cat donnees_client)
        client_uuid=$(echo $data_client | tr -s " " | cut -d " " -f1)
        client_malade=$(echo $data_client | tr -s " " | cut -d " " -f2)
        client_contact=$(echo $data_client | tr -s " " | cut -d " " -f3)

        echo "$client_uuid $client_malade $client_contact $coords" > donnees_client
        openssl rsautl -in donnees_client -out $DATA_FOLDER/client_data -pubin -inkey $KEY_FOLDER/client.pub -encrypt
        rm donnees_client
}


while test $# -gt 0; do
        case "$1" in
                -d|--debug)
                        shift
                        DEBUG=1
                        ;;
		-m|--malade)
			shift
			marquerMalade "true"
			exit 0
			;;
		-s|--soigne)
			shift
			marquerMalade "false"
			exit 0
			;;
		-i|--infos)
			shift
			afficherInfoClient
			exit 0
			;;
		-g|--gps)
			shift
			updateGPS $1
			shift
			exit 0
			;;
		*)
			shift
			;;
        esac
done


# Initialisation

if [[ ! -d $DATA_FOLDER ]]; then
        mkdir $DATA_FOLDER
fi

if [[ ! -d $KEY_FOLDER ]]; then
         mkdir $KEY_FOLDER
fi

# On commence par vérifier si l'utilisateur possède un jeu de clé pub/priv
if [[ ! -f $KEY_FOLDER/client.key ]]; then
        dprint "[+] Génération de la clé privée du client"
        openssl genrsa -out $KEY_FOLDER/client.key #$DISABLE_OUTPUT
fi
if [[ ! -f $KEY_FOLDER/client.pub ]]; then
        dprint "[+] Génération de la clé publique du client"
        openssl rsa -in $KEY_FOLDER/client.key -pubout -out $KEY_FOLDER/client.pub #$DISABLE_OUTPUT
fi


# On vérifie maintenant si l'utilisateur possède des données
if [[ ! -f $DATA_FOLDER/client_data ]]; then
        dprint "[+] Nouvel utilisateur, on crée son compte, il n'est pas malade ni cas contact"
        uuid=$(genererUUID)
        coords=$(genererRandomCoords)
        echo "$uuid false false $coords" > .tmp
        dprint "[+] Chiffrements de nos données en cours"
	openssl rsautl -in .tmp -out $DATA_FOLDER/client_data -pubin -inkey $KEY_FOLDER/client.pub -encrypt
	rm .tmp

fi

# On définit les permissions des données
chmod u+rwx,g-rwx,o-rwx $DATA_FOLDER/client_data $KEY_FOLDER/client.pub $KEY_FOLDER/client.key $DATA_FOLDER $KEY_FOLDER

# CLIENT

# On vérifie tout d'abord si le fichier existe

dprint "[+] Génération du fichier client.txt"

echo "$ip_client $port_client" > client.txt

# Envoie client.txt au serveur
dprint "[+] Envoie du fichier client.txt au serveur"
send_message $HOST $PORT < client.txt


# On recoit le DHPARAMS
dprint "[-] En attente de DHPARAMS"
recv_message > dhparams.pem
dprint "[+] DHPARAMS reçu"

sleep 1
# On génère notre clé publique & privée
dprint "[+] Génération de notre clé privée"
openssl genpkey -paramfile dhparams.pem -out client.key
dprint "[+] Génération de notre clé publique"
openssl pkey -in client.key -pubout -out client.pub

# On envoie notre clé publique au serveur
dprint "[+] Envoie de notre clé publique au serveur"
send_message $HOST $PORT < client.pub

# On attend la clé publique du serveur
dprint "[-] En attente de la cle publique du serveur"
recv_message > server_key.pub

# On dérive la clé
dprint "[+] Dérivation de la clé"
openssl pkeyutl -derive -inkey client.key -peerkey server_key.pub -out common.key

# On déchiffre avant de les envoyer
dprint "[+] Déchiffrement de nos données avant de les envoyer au serveur"
openssl rsautl -in $DATA_FOLDER/client_data -out donnees_client -inkey $KEY_FOLDER/client.key -decrypt

# On chiffre nos coordonnées avec la clé publique du serveur
dprint "[+] Chiffrement de nos données"
openssl aes-128-cbc -e -K $(head -c 16 common.key | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 common.key | hexdump -v -e '/1 "%02x"') -in donnees_client -out donnes.enc


# On supprime le fichier
dprint "[+] Suppression du fichier déchiffré"
rm donnees_client

# On envoie nos données
dprint "[+] Envoie de nos données en cours"
send_message $HOST $PORT < donnes.enc

# On attend une réponse du serveur
dprint "[-] On attend la réponse du serveur avec nos données"
recv_message > reponse.enc

# On décrypte les données
openssl aes-128-cbc -d -K $(head -c 16 common.key | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 common.key | hexdump -v -e '/1 "%02x"') -in reponse.enc -out donnes.dec

# On affiche ce qu'on a reçu
reponse_srv=$(cat donnes.dec)
malade=$(echo $reponse_srv | tr -s " " | cut -d " " -f1)
cas_contact=$(echo $reponse_srv | tr -s " " | cut -d " " -f2)
dprint "[#] Un malade est dans notre zone: $malade | Un cas contact est dans notre zone: $cas_contact"

# Si un malade a été detecté; nous sommes désormais cas contact
# On va donc modifier notre fichier de données
openssl rsautl -in $DATA_FOLDER/client_data -out donnees_client -inkey $KEY_FOLDER/client.key -decrypt
data_client=$(cat donnees_client)
client_uuid=$(echo $data_client | tr -s " " | cut -d " " -f1)
client_malade=$(echo $data_client | tr -s " " | cut -d " " -f2)
client_contact=$(echo $data_client | tr -s " " | cut -d " " -f3)
client_x=$(echo $data_client | tr -s " " | cut -d " " -f4)
client_y=$(echo $data_client | tr -s " " | cut -d " " -f5)

if [[ $malade == "true" ]]; then
	client_contact="true"
fi

# On stock les nouvelles données
dprint "[-] Stockage des nouvelles données"
echo "$client_uuid $client_malade $client_contact $client_x $client_y" > donnees_client
openssl rsautl -in donnees_client -out $DATA_FOLDER/client_data -pubin -inkey $KEY_FOLDER/client.pub -encrypt

# ON nettoie le tout
dprint "[-] Nettoyage des fichiers"
rm client.key client.pub common.key dhparams.pem donnes.enc reponse.enc server_key.pub client.txt donnes.dec donnees_client
