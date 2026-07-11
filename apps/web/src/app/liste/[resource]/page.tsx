import { notFound } from "next/navigation";
import { resourceByKey } from "@/server/domains/registry";
import { ResourceBrowser } from "@/components/ResourceBrowser";

export const dynamic = "force-dynamic";

export default async function ResourcePage({ params }: { params: Promise<{ resource: string }> }) {
  const { resource } = await params;
  const res = resourceByKey(resource);
  if (!res) notFound();
  return <ResourceBrowser resource={res.key} label={res.label} image={res.image ?? undefined} download={res.download} actions={res.actions} backHref={`/bereich/${res.domain}`} />;
}
