namespace LumaShot.Core;

public enum AnnotationTool { Select, Arrow, Rectangle, Ellipse, Pen, Text, Number, Mosaic, Hand }
public readonly record struct ImagePoint(double X, double Y)
{
    public ImagePoint Offset(double x, double y) => new(X + x, Y + y);
}
public readonly record struct ImageBounds(double X, double Y, double Width, double Height)
{
    public bool Contains(ImagePoint p, double padding = 0) => p.X >= X - padding && p.X <= X + Width + padding && p.Y >= Y - padding && p.Y <= Y + Height + padding;
}

public sealed record Annotation(AnnotationTool Tool, ImagePoint[] Points, uint Color = 0xFF7D59EF,
    double StrokeWidth = 4, string Text = "", double FontSize = 28, int Number = 1)
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public Annotation Copy() => this with { Points = (ImagePoint[])Points.Clone() };
    public Annotation Move(double x, double y) => this with { Points = Points.Select(p => p.Offset(x, y)).ToArray() };
    public ImageBounds Bounds
    {
        get
        {
            if (Points.Length == 0) return default;
            if (Tool == AnnotationTool.Text)
            {
                var lines = Text.Split('\n');
                return new(Points[0].X, Points[0].Y, Math.Max(FontSize, lines.Max(l => l.Sum(c => c > 255 ? 1.0 : .65)) * FontSize), lines.Length * FontSize * 1.4);
            }
            if (Tool == AnnotationTool.Number) return new(Points[0].X - FontSize, Points[0].Y - FontSize, FontSize * 2, FontSize * 2);
            var minX = Points.Min(p => p.X); var minY = Points.Min(p => p.Y);
            return new(minX, minY, Math.Max(1, Points.Max(p => p.X) - minX), Math.Max(1, Points.Max(p => p.Y) - minY));
        }
    }
}

public sealed class AnnotationDocument
{
    private List<Annotation> items = [];
    private readonly List<List<Annotation>> undo = [];
    private readonly List<List<Annotation>> redo = [];
    public IReadOnlyList<Annotation> Items => items;
    public bool CanUndo => undo.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public event Action? Changed;
    private static List<Annotation> Snapshot(IEnumerable<Annotation> source) => source.Select(a => a.Copy()).ToList();
    private void Edit(Action operation)
    {
        undo.Add(Snapshot(items)); if (undo.Count > 80) undo.RemoveAt(0);
        redo.Clear(); operation(); Changed?.Invoke();
    }
    public void Add(Annotation annotation) { if (annotation.Points.Length > 0) Edit(() => items.Add(annotation.Copy())); }
    public void Replace(Annotation annotation)
    {
        var i = items.FindIndex(a => a.Id == annotation.Id);
        if (i >= 0) Edit(() => items[i] = annotation.Copy());
    }
    public void Delete(Guid id) { if (items.Any(a => a.Id == id)) Edit(() => items.RemoveAll(a => a.Id == id)); }
    public void Clear() { if (items.Count > 0) Edit(items.Clear); }
    public void Undo()
    {
        if (!CanUndo) return; redo.Add(Snapshot(items)); items = undo[^1]; undo.RemoveAt(undo.Count - 1); Changed?.Invoke();
    }
    public void Redo()
    {
        if (!CanRedo) return; undo.Add(Snapshot(items)); items = redo[^1]; redo.RemoveAt(redo.Count - 1); Changed?.Invoke();
    }
}
