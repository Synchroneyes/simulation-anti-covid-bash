#!/bin/bash +x


PORT=1001
DATA_FOLDER="data"
DISABLE_OUTPUT="> /dev/null 2>&1"
ack="ACK"
function send_message() {
    [ $# -lt 2 ] && echo "Usage: $FUNCNAME <host> <port>" >&2 && return 1
    local HOST=$1
    local PORT=$2

    cat | nc -q 0 $HOST $PORT
}

function recv_message() {
    nc -q 0 -lp $PORT
}


# Debug print
function dprint(){
	[ $# -lt 1 ] && echo "Usage: $FUNCNAME MESSAGE" >&2 && return 1
	[ $DEBUG -eq 1 ] && echo $1
}


# Chiffre, $1 = Client
# $1 = IP_Client
# $2 = Fichier
function encrypt(){
	[ $# -lt 2 ] && echo "$# Usage: $FUNCNAME IP MESSAGE" >&2 && return 1
	openssl aes-128-cbc -e -K $(head -c 16 $DATA_FOLDER/keys/$1.common | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 $DATA_FOLDER/keys/$1.common | hexdump -v -e '/1 "%02x"') -out $2.enc -in $2
	result=$(cat $2.enc)
	echo $result
}


# Dechiffre
# $1 = IP_Client
# $2 = fichier
function decrypt(){
	[ $# -lt 2 ] && echo "Usage: $FUNCNAME IP MESSAGE" >&2 && return 1
	
	openssl aes-128-cbc -d -K $(head -c 16 $DATA_FOLDER/keys/$1.common | hexdump -v -e '/1 "%02x"')  -iv $(head -c 16 $DATA_FOLDER/keys/$1.common | hexdump -v -e '/1 "%02x"') -out $2 -in $2.enc
	dechiffre=$(cat $2)
	echo $dechiffre
}

DEBUG=0



while test $# -gt 0; do
        case "$1" in
                -d|--debug)
                        shift
                        DEBUG=1
                        ;;
        esac
done

# Vérification du DHPARAMS
if [ ! -d $DATA_FOLDER ]; then
        mkdir $DATA_FOLDER
fi

if [ ! -d $DATA_FOLDER/positions ]; then
	mkdir $DATA_FOLDER/positions
fi

# On commence par vérifier le fichier dhparam
[ ! -f "$DATA_FOLDER/dhparams.pem" ]  && [ $DEBUG -eq 0 ] && echo "[-] Generation dhparams" && openssl dhparam -outform PEM -out $DATA_FOLDER/dhparams.pem -2 $DISABLE_OUTPUT
[ ! -f "$DATA_FOLDER/dhparams.pem" ]  && [ $DEBUG -eq 1 ] && echo "[-] Generation dhparams" && openssl dhparam -outform PEM -out $DATA_FOLDER/dhparams.pem -2

while [ 1 -eq 1 ]; do
        [ $DEBUG -eq 1 ] && echo "[-] En attente d'une connexion client"
        # Attend une connexion client
        INFO_CLIENT=$(recv_message)
	client_ip=$(echo $INFO_CLIENT | tr -s " " | cut -d " " -f1)
	client_port=$(echo $INFO_CLIENT | tr -s " " | cut -d " " -f2)
	dprint "[+] Information client: $client_ip:$client_port"
	
	sleep 1
	dprint "[+] Envoie du DHPARAMS"
	send_message $client_ip $client_port < $DATA_FOLDER/dhparams.pem

	# On attend de recevoir les infos du client (uuid, cle publique, gps)
	# On commence par la cle publique
	[ ! -d "$DATA_FOLDER/keys" ] && mkdir $DATA_FOLDER/keys
	dprint "[-] En attente de la cle publique du client"
	recv_message > $DATA_FOLDER/keys/$client_ip.pubclient
	
	# On genere une cle publique pour le serveur pour ce client
	# On génère notre clé publique & privée
	dprint "[+] Generation de notre cle privee"
	openssl genpkey -paramfile $DATA_FOLDER/dhparams.pem -out $DATA_FOLDER/keys/$client_ip.keysrv
	dprint "[+] Generation de notre cle publique"
	openssl pkey -in $DATA_FOLDER/keys/$client_ip.keysrv -pubout -out $DATA_FOLDER/keys/$client_ip.pubsrv
	
	# On derive la cle pour generer une cle commune
	dprint "[+] Derivation de la cle"
	openssl pkeyutl -derive -inkey $DATA_FOLDER/keys/$client_ip.keysrv -peerkey $DATA_FOLDER/keys/$client_ip.pubclient -out $DATA_FOLDER/keys/$client_ip.common

	# On envoie notre cle publique au client
	dprint "[+] Envoie de notre cle publique au client"
	send_message $client_ip $client_port < $DATA_FOLDER/keys/$client_ip.pubsrv

	# On attend de recevoir le fichier info client contenant:
	# UUID	GPSx	GPSy
	dprint "[-] En attente des infos clients GPS, ...."
	recv_message > $client_ip-data.enc
	
	dprint "[+] Dechiffrement des donnes en cours"
	data_client=$(decrypt $client_ip $client_ip-data)
	
	client_uuid=$(echo $data_client | tr -s " " | cut -d " " -f1)
	client_malade=$(echo $data_client | tr -s " " | cut -d " " -f2)
	client_contact=$(echo $data_client | tr -s " " | cut -d " " -f3)
	client_x=$(echo $data_client | tr -s " " | cut -d " " -f4)
	client_y=$(echo $data_client | tr -s " " | cut -d " " -f5)

	dprint "[+] Suppression des fichiers de data"
        rm $client_ip-data $client_ip-data.enc

	dprint "[?] $client_uuid est malade: $client_malade, il est cas contact: $client_contact, il se trouve en [$client_x,$client_y]"
	dprint "[-] On verifie si un cas contact/malade est dans la zone"
	
	# On enregistre les donnees dans la bd
	# Pour cet exemple, on suppose que seuls les clients presant dans la meme zone ont des risques de contamination
	# On commence par supprimer les donnees connus d'une personne pour la remplacer
	dprint "[-] Suppression des anciennes donnees de l'utilisateur"
	rm $DATA_FOLDER/positions/*/*/$client_uuid > /dev/null 2>&1
	
	# On enregistre ses donnees
	
	dprint "[-] Enregistrement des donnees d'utilisateurs"
	mkdir -p $DATA_FOLDER/positions/$client_x/$client_y
	echo "$client_malade $client_contact" > $DATA_FOLDER/positions/$client_x/$client_y/$client_uuid
	
	dprint "[-] Verification des cas contacts/malade"
	emplacement_localisation="$DATA_FOLDER/positions/$client_x/$client_y"
	cas_contact_detecter=false
	malade_detecter=false
	for personne in `ls $emplacement_localisation`; do
		if [[ $personne != $client_uuid ]]; then
			dprint "[#] Comparaison de $client_uuid avec $personne"
			# cas malade
			cm=$(cat $emplacement_localisation/$personne | tr -s " " | cut -d " " -f1)
			# cas contact
			cc=$(cat $emplacement_localisation/$personne | tr -s " " | cut -d " " -f2)

			if [[ $cc == "true" ]]; then
				dprint "[-] Cas contact detecte"
				cas_contact_detecter=true
			fi
			
			if [[ $cm == "true" ]]; then
				dprint "[!] Malade detecte dans la zone !"
                                malade_detecter=true
				break
                        fi
		fi
	done

	echo "$malade_detecter $cas_contact_detecter" > $client_uuid.resp
	to_send=$(encrypt $client_ip $client_uuid.resp)
	
	dprint "[+] Envoie des donnees au client"
	send_message $client_ip $client_port < $client_uuid.resp.enc

	dprint "[-] Nettoyage des fichiers"
	rm $client_uuid.resp.enc $client_uuid.resp
	
	dprint "[#] FIN DU TRAITEMENT CLIENT"
	dprint "---------------------------------"
done
