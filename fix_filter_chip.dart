class _ModernFilterChip extends StatefulWidget {
  final ThemeData theme;
  final String label;
  final bool isActive;
  final void Function(BuildContext context, LayerLink link) onTap;

  const _ModernFilterChip({
    Key? key,
    required this.theme,
    required this.label,
    required this.isActive,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_ModernFilterChip> createState() => _ModernFilterChipState();
}

class _ModernFilterChipState extends State<_ModernFilterChip> {
  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(context, _layerLink),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.sclass _ModernFilterChip extends Sta8)  final ThemeData theme;
  final String label;
    final String label;
 is  final bool isActiv    final void Function  
  const _ModernFilterChip({
    Key? key,
    required this.theme.c    Key? key,
    requiredci    required      required this.labelge    required this.isActma    required this.onTap,
     }) : super(key: key);                )
           State<_M n}

class _ModernFilterChipState extends State<_ModernFilterChip> {
        final LayerLink _layerLink = LayerLink();

  @override
  Wid.w
  @override
  Widget build(BuildContext cs:   Widget bus    return CompositedTransformTarget(Bo      link: _layerLink,
      child:ge      child: Material(          color: Colors.c        child: InkWell(
         4)          onTap: () => w          borderRadius: BorderRadius.circular(20),
     
           child: AnimatedContainer(
            d              duration: const Durati              padd(
              mainAxisSize: MainAxisSiz  final String label;
    final String label;
 is  final bool isActiv    final void Function  
  co      final String labem is  final bool isActim?  const _ModernFilterChip({
    Key? key,
    rAc    Key? key,
    required      requiredem    requiredci    required      requi       }) : super(key: key);                )
           State<_M n}

class _ModernFilterChipState exte F           State<_M n}

class _ModernFilte  
class _ModernFilterC           final LayerLink _layerLink = LayerLink();

  @override  
  @override
  Wid.w
  @override
  Widget build(n_rounded,
      @ove    Widget b:       child:ge      child: Material(          color: Colors.c        child: InkWell(
         4)                            : widget.theme.colorScheme.onSurfaceVariant,
                ),
         
           c       ),
          ),
        ),
      ),
    );
  }
}
