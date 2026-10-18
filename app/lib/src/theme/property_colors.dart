import 'package:flutter/material.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';

/// Maps each [PropertyColor] to the color swatch used on the physical
/// cards, so a color group reads at a glance the same way it does on the
/// table.
const Map<PropertyColor, Color> propertySwatch = {
  PropertyColor.brown: Color(0xFF8B4A2B),
  PropertyColor.lightBlue: Color(0xFF9BD4EA),
  PropertyColor.pink: Color(0xFFE6399B),
  PropertyColor.orange: Color(0xFFF7941D),
  PropertyColor.red: Color(0xFFE0282E),
  PropertyColor.yellow: Color(0xFFFCE300),
  PropertyColor.green: Color(0xFF1FA858),
  PropertyColor.darkBlue: Color(0xFF0A5BA8),
  PropertyColor.railroad: Color(0xFF2B2B2B),
  PropertyColor.utility: Color(0xFFBFDCC8),
};

Color propertyForegroundFor(PropertyColor color) {
  switch (color) {
    case PropertyColor.yellow:
    case PropertyColor.lightBlue:
    case PropertyColor.utility:
      return Colors.black87;
    default:
      return Colors.white;
  }
}

String propertyColorLabel(PropertyColor color) {
  switch (color) {
    case PropertyColor.brown:
      return 'Brown';
    case PropertyColor.lightBlue:
      return 'Light Blue';
    case PropertyColor.pink:
      return 'Pink';
    case PropertyColor.orange:
      return 'Orange';
    case PropertyColor.red:
      return 'Red';
    case PropertyColor.yellow:
      return 'Yellow';
    case PropertyColor.green:
      return 'Green';
    case PropertyColor.darkBlue:
      return 'Dark Blue';
    case PropertyColor.railroad:
      return 'Railroad';
    case PropertyColor.utility:
      return 'Utility';
  }
}

String actionTypeLabel(ActionType type) {
  switch (type) {
    case ActionType.dealBreaker:
      return 'Deal Breaker';
    case ActionType.justSayNo:
      return 'Just Say No!';
    case ActionType.slyDeal:
      return 'Sly Deal';
    case ActionType.forcedDeal:
      return 'Forced Deal';
    case ActionType.debtCollector:
      return 'Debt Collector';
    case ActionType.itsMyBirthday:
      return "It's My Birthday";
    case ActionType.passGo:
      return 'Pass Go';
    case ActionType.house:
      return 'House';
    case ActionType.hotel:
      return 'Hotel';
    case ActionType.doubleTheRent:
      return 'Double The Rent';
  }
}

String actionTypeDescription(ActionType type) {
  switch (type) {
    case ActionType.dealBreaker:
      return 'Steal a complete property set from any player.';
    case ActionType.justSayNo:
      return 'Use any time an action card is played against you.';
    case ActionType.slyDeal:
      return "Steal a property from any player's incomplete set.";
    case ActionType.forcedDeal:
      return "Swap a property with another player's property.";
    case ActionType.debtCollector:
      return 'Force one player to pay you \$5M.';
    case ActionType.itsMyBirthday:
      return 'All players give you \$2M.';
    case ActionType.passGo:
      return 'Draw 2 extra cards.';
    case ActionType.house:
      return 'Add to any complete set you own: +\$3M rent.';
    case ActionType.hotel:
      return 'Add to a set with a House: +\$4M rent.';
    case ActionType.doubleTheRent:
      return 'Play with a Rent card to double it.';
  }
}
