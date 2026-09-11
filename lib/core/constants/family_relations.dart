const familyRelations = [
  'Father',
  'Mother',
  'Brother',
  'Sister',
  'Son',
  'Daughter',
  'Grandfather',
  'Grandmother',
  'Uncle',
  'Aunt',
  'Cousin',
  'Guest',
];

String relationshipLabelFor({
  required String currentUserRelation,
  required String memberRelation,
  bool isCurrentUser = false,
}) {
  if (isCurrentUser) return 'You';

  final relation = _relativeRole(
    currentUserRelation: currentUserRelation,
    memberRelation: memberRelation,
  );
  return relation;
}

String _relativeRole({
  required String currentUserRelation,
  required String memberRelation,
}) {
  final current = currentUserRelation.toLowerCase();
  final member = memberRelation.toLowerCase();

  final currentIsParent = current == 'father' || current == 'mother';
  final memberIsParent = member == 'father' || member == 'mother';
  final memberIsSibling = member == 'brother' || member == 'sister';
  final memberIsChild = member == 'son' || member == 'daughter';
  final memberIsChildGeneration = memberIsSibling || memberIsChild;

  if (currentIsParent && memberIsChildGeneration) {
    return member == 'sister' || member == 'daughter' ? 'Daughter' : 'Son';
  }

  if (current == 'brother' || current == 'sister' || currentIsChild(current)) {
    if (memberIsParent) return memberRelation;
    if (memberIsSibling) return memberRelation;
  }

  if ((current == 'grandfather' || current == 'grandmother') &&
      memberIsChildGeneration) {
    return member == 'sister' || member == 'daughter'
        ? 'Granddaughter'
        : 'Grandson';
  }

  if ((current == 'uncle' || current == 'aunt') && memberIsChildGeneration) {
    return member == 'sister' || member == 'daughter' ? 'Niece' : 'Nephew';
  }

  if (current == 'cousin' && member == 'cousin') return 'Cousin';

  return memberRelation.isEmpty ? 'Member' : memberRelation;
}

bool currentIsChild(String current) {
  return current == 'son' || current == 'daughter';
}
