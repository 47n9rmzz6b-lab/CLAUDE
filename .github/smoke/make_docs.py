#!/usr/bin/env python3
"""Documents de test : texte court, rapport long, PDF, document Word et image."""
import os
import random
import struct
import subprocess
import sys
import zlib

out = sys.argv[1]
tools = os.path.dirname(os.path.abspath(__file__))
os.makedirs(out, exist_ok=True)


def write(name, text):
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        f.write(text)


write("notes-projet.txt", "Notes de l'atelier\n\nLe code du coffre de l'atelier est 4721.\n"
      "La prochaine réunion d'équipe a lieu jeudi à 9 h.\n")

sentences = [
    "L'équipe a revu l'organisation des plannings pour les prochains mois.",
    "Les fournisseurs habituels ont confirmé les délais de livraison annoncés.",
    "La salle de réunion du deuxième étage sera repeinte au printemps.",
    "Plusieurs collègues ont suivi une formation sur les outils collaboratifs.",
    "Le service informatique prévoit de remplacer les anciens ordinateurs portables.",
    "Les retours des clients sur la nouvelle interface sont globalement positifs.",
    "Un groupe de travail étudie la réduction de la consommation d'énergie.",
    "Les archives papier seront numérisées d'ici la fin de l'année.",
    "La cafétéria proposera désormais des menus végétariens le mercredi.",
    "Le comité de direction se réunira une fois par trimestre.",
]
random.seed(7)
paragraphs = []
for number in range(40):
    random.shuffle(sentences)
    paragraphs.append(f"Section {number + 1}. " + " ".join(sentences[:6]))
paragraphs.insert(22, "Section budgétaire. Le budget total du projet Hibiscus s'élève à 12 000 euros, "
                      "validé par Mme Durand le 3 février. Cette enveloppe couvre le matériel et la formation.")
write("rapport-long.txt", "Rapport d'activité annuel\n\n" + "\n\n".join(paragraphs) + "\n")

# PDF (texte réel, extrait par PDFKit dans l'app).
write("lettre.txt", "Lettre d'information\n\nLa réunion annuelle aura lieu le 14 mars à Grenoble, salle Belledonne.\n"
      "Merci de confirmer votre présence avant le 1er mars.\n")
subprocess.run(["swift", os.path.join(tools, "make_pdf.swift"), os.path.join(out, "lettre.txt"), os.path.join(out, "lettre.pdf")], check=False)
os.remove(os.path.join(out, "lettre.txt"))

# Document Word.
write("memo.txt", "Mémo interne\n\nLe mot de passe du wifi de l'atelier est Lavande-2026.\n")
subprocess.run(["textutil", "-convert", "docx", "-output", os.path.join(out, "memo.docx"), os.path.join(out, "memo.txt")], check=False)
os.remove(os.path.join(out, "memo.txt"))


# Image : un disque rouge et un carré bleu sur fond blanc.
def png(path, width=360, height=240):
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            if (x - 110) ** 2 + (y - 120) ** 2 <= 70 ** 2:
                row += bytes((215, 35, 35))
            elif 200 <= x <= 320 and 60 <= y <= 180:
                row += bytes((35, 70, 210))
            else:
                row += bytes((255, 255, 255))
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


png(os.path.join(out, "formes.png"))
for name in sorted(os.listdir(out)):
    print(name, os.path.getsize(os.path.join(out, name)))
