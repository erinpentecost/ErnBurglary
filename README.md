# ErnBurglary
OpenMW mod that overhauls theft. No longer will NPCs forget that you were in their house when all their gems were stolen.

## Witnesses and Punishment
If an NPC greets you, they will remember that you are in the area. If their stuff disappeared before you left, you'll be caught *after-the-fact*. This punishment is less severe than *red-handed* theft: the value of the stolen goods will be subtracted from the owner's disposition until it hits 0. Any leftover value will be converted into bounty.

Stolen items that belong to a faction will get reported if any member of that faction remembers you in the area. You can optionally reduce your faction reputation, and have the excess converted into bounty and explusion (if you are member).

Guards look out for everyone's items, not just their own.

If witnesses are dead before you leave the area, they won't report the theft.

## Red-handed Theft
The punishment for red-handed theft is reduced to a token 1 gp in order to avoid double-jeopardy. You'll be penalized when you leave.

## Indicators
- While you're spotted in the area, a 5pt Drain Sneak effect is applied. This is removed as soon as you're no longer spotted.
- When you enter sneak mode, you'll get an alert if you were previously spotted.
- If you're spotted while in sneak mode, you'll also get an alert.
- If all the witnesses die, you'll get another alert.
- If you get caught when you leave, you'll get an alert.
settings.inferOwnership() then
            -- Gross workaround to guess the owner.
            owner = inferAreaOwner(actor.cell.id, actor.id)
## How it Works
If you're near an NPC and they say something, they will be marked as having spotted you. This also applies for idle sounds, since I haven't found a way to filter those out yet.

![a thief with a big bag, created with AI](title_image.jpg)

## Installing
Extract [main](https://github.com/erinpentecost/ErnBurglary/archive/refs/heads/main.zip) to your `mods/` folder.


In your `openmw.cfg` file, and add these lines in the correct spots:

```yaml
data="/wherevermymodsare/mods/ErnBurglary-main"
content=ErnBurglary.omwaddon
content=ErnBurglary.omwscripts
```

## Contributing

Feel free to submit a PR to the [repo](https://github.com/erinpentecost/ErnBurglary) provided you certify your contribution under the [Developer Certificate of Origin](https://developercertificate.org/).

### omwaddon
The omwaddon contains these entries:
* `fCrimeStealing` penalty set to 0.
* `ernburglary_spotted` spell that contains the penalty for being spotted.
