local _, ns = ...

local L = {
	PLACEHOLDER    = "Search a member",
	NO_RESULT      = "No member found",
	MOBILE         = "On mobile",
	NOTE           = "Note: %s",
	OFFICER_NOTE   = "Officer note: %s",
	HINT_MENU      = "Right-click a result for the usual member menu",
	HINT_MOVE      = "Alt + drag the search bar to move it",
	HELP_TITLE     = "Guild Search Bar commands:",
	HELP_NOTES     = "/gsb notes - also search in notes (now: %s)",
	HELP_RESET     = "/gsb reset - put the search bar back in its default place",
	ON             = "on",
	OFF            = "off",
	RESET_DONE     = "Search bar position reset.",
	NOTES_TOGGLED  = "Search in notes: %s.",
}

if GetLocale() == "frFR" then
	L.PLACEHOLDER    = "Rechercher un membre"
	L.NO_RESULT      = "Aucun membre trouvé"
	L.MOBILE         = "Sur mobile"
	L.NOTE           = "Note : %s"
	L.OFFICER_NOTE   = "Note d'officier : %s"
	L.HINT_MENU      = "Clic droit sur un résultat pour le menu habituel du membre"
	L.HINT_MOVE      = "Alt + glisser la barre de recherche pour la déplacer"
	L.HELP_TITLE     = "Commandes de Guild Search Bar :"
	L.HELP_NOTES     = "/gsb notes - chercher aussi dans les notes (actuellement : %s)"
	L.HELP_RESET     = "/gsb reset - remettre la barre de recherche à sa place d'origine"
	L.ON             = "activé"
	L.OFF            = "désactivé"
	L.RESET_DONE     = "Position de la barre de recherche réinitialisée."
	L.NOTES_TOGGLED  = "Recherche dans les notes : %s."
end

ns.L = L
